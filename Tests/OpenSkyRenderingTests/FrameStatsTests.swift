// FrameStats window flush: drives synthetic frames through the instrument and
// asserts the summary line and the live snapshot carry CPU and GPU figures.

import Foundation
@testable import OpenSkyRendering
import Testing

struct FrameStatsTests {
    @Test func flushesSummaryAfterWindow() throws {
        let stats = FrameStats()

        var summary: String?
        for frame in 0 ..< 120 {
            let start = stats.beginFrame()
            stats.gpuSpans.record(start: 10, end: 10.004)
            let flushed = stats.endFrame(cpuStartNS: start)
            if frame < 119 {
                #expect(flushed == nil, "window must not flush before 120 frames")
            } else {
                summary = flushed
            }
        }

        let line = try #require(summary, "120th frame closes the stats window")
        #expect(line.contains("fps"))
        #expect(line.contains("cpu encode avg"))
        #expect(line.contains("gpu avg 4.00 ms"))
    }

    /// The live window must not perturb the log window: the summary still
    /// arrives on frame 120 and nowhere else, with the same shape.
    @Test func liveWindowLeavesLogWindowIntact() throws {
        let stats = FrameStats()

        var flushCount = 0
        var summary: String?
        for _ in 0 ..< 120 {
            let start = stats.beginFrame()
            if let line = stats.endFrame(cpuStartNS: start) {
                flushCount += 1
                summary = line
            }
            // Polling mid-window is what the panel and the HUD do at 2 Hz.
            _ = stats.snapshot()
        }

        #expect(flushCount == 1, "exactly one 120-frame window closed")
        let line = try #require(summary)
        #expect(line.contains("frame avg"))
        #expect(line.contains("cpu encode avg"))
        #expect(line.contains("gpu avg n/a"))
    }

    @Test func snapshotIsEmptyBeforeFirstLiveWindow() {
        let stats = FrameStats()

        #expect(stats.snapshot() == .empty)
        #expect(stats.snapshot().hasMeasurement == false)

        // 29 frames is one short of the 30-frame live window.
        for _ in 0 ..< 29 {
            let start = stats.beginFrame()
            stats.endFrame(cpuStartNS: start)
        }
        #expect(stats.snapshot() == .empty)
    }

    @Test func snapshotReportsLiveWindowFigures() throws {
        let stats = FrameStats()

        for _ in 0 ..< 30 {
            let start = stats.beginFrame()
            stats.gpuSpans.record(start: 5, end: 5.002)
            stats.endFrame(cpuStartNS: start)
        }

        let snapshot = stats.snapshot()
        #expect(snapshot.hasMeasurement)
        #expect(snapshot.sampleCount == 30)
        // 29 intervals over 30 frames; CPU figures come from real elapsed time,
        // so assert the invariants rather than exact values.
        #expect(snapshot.frameMS > 0)
        #expect(snapshot.maxFrameMS >= snapshot.frameMS)
        #expect(snapshot.encodeMS >= 0)
        #expect(abs(snapshot.fps * snapshot.frameMS - 1000) < 0.001)
        let gpuMS = try #require(snapshot.gpuMS)
        #expect(abs(gpuMS - 2) < 0.001)
    }

    /// A late feedback span counts once, in the frame that takes it.
    @Test func gpuSpansAreTakenOnce() {
        let inbox = GPUSpanInbox()
        inbox.record(start: 1, end: 1.001)
        inbox.record(start: 2, end: 1.5)
        let first = inbox.take()
        #expect(first.count == 1)
        #expect(first.totalNS == 1_000_000)
        #expect(inbox.take().totalNS == 0)
    }
}
