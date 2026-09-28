// FrameStats window flush: drives 120 synthetic frames through the
// instrument and asserts the summary line — the 2.9 fps-gate measurement —
// actually materializes with CPU and GPU figures. Needs a Metal device for
// timestamp correlation (skipped on CI without one).

import Foundation
import Metal
@testable import opensky
import Testing

struct FrameStatsTests {
    private static let device = MTLCreateSystemDefaultDevice()

    private static var hasDevice: Bool {
        device != nil
    }

    @Test(.enabled(if: Self.hasDevice)) func flushesSummaryAfterWindow() throws {
        let device = try #require(Self.device)
        let stats = FrameStats(device: device)

        var summary: String?
        var tick: UInt64 = 1000
        for frame in 0 ..< 120 {
            let start = stats.beginFrame()
            let flushed = stats.endFrame(
                cpuStartNS: start,
                gpuTicks: (start: tick, end: tick + 500)
            )
            tick += 1000
            if frame < 119 {
                #expect(flushed == nil, "window must not flush before 120 frames")
            } else {
                summary = flushed
            }
        }

        let line = try #require(summary, "120th frame closes the stats window")
        #expect(line.contains("fps"))
        #expect(line.contains("cpu encode avg"))
        // GPU figure is numeric only where sampleTimestamps advances (real
        // hardware); paravirtual CI GPUs legitimately report n/a.
        #expect(line.contains("gpu avg"))
    }

    /// The live window must not perturb the log window: the summary still
    /// arrives on frame 120 and nowhere else, with the same shape.
    @Test(.enabled(if: Self.hasDevice)) func liveWindowLeavesLogWindowIntact() throws {
        let device = try #require(Self.device)
        let stats = FrameStats(device: device)

        var flushCount = 0
        var summary: String?
        for _ in 0 ..< 120 {
            let start = stats.beginFrame()
            if let line = stats.endFrame(cpuStartNS: start, gpuTicks: nil) {
                flushCount += 1
                summary = line
            }
            // Polling mid-window is what the panel and the HUD do at 2 Hz.
            _ = stats.snapshot()
        }

        #expect(flushCount == 1, "exactly one 120-frame window closed")
        let line = try #require(summary)
        #expect(line.contains("frame avg"))
        #expect(line.contains("fps"))
        #expect(line.contains("cpu encode avg"))
        #expect(line.contains("gpu avg"))
    }

    @Test(.enabled(if: Self.hasDevice)) func snapshotIsEmptyBeforeFirstLiveWindow() throws {
        let device = try #require(Self.device)
        let stats = FrameStats(device: device)

        #expect(stats.snapshot() == .empty)
        #expect(stats.snapshot().hasMeasurement == false)

        // 29 frames is one short of the 30-frame live window.
        for _ in 0 ..< 29 {
            let start = stats.beginFrame()
            stats.endFrame(cpuStartNS: start, gpuTicks: nil)
        }
        #expect(stats.snapshot() == .empty)
    }

    @Test(.enabled(if: Self.hasDevice)) func snapshotReportsLiveWindowFigures() throws {
        let device = try #require(Self.device)
        let stats = FrameStats(device: device)

        var tick: UInt64 = 1000
        for _ in 0 ..< 30 {
            let start = stats.beginFrame()
            stats.endFrame(cpuStartNS: start, gpuTicks: (start: tick, end: tick + 500))
            tick += 1000
        }

        let snapshot = stats.snapshot()
        #expect(snapshot.hasMeasurement)
        #expect(snapshot.sampleCount == 30)
        // 29 intervals over 30 frames; every figure comes from real elapsed
        // time, so assert the invariants rather than exact values.
        #expect(snapshot.frameMS > 0)
        #expect(snapshot.maxFrameMS >= snapshot.frameMS)
        #expect(snapshot.encodeMS >= 0)
        #expect(snapshot.fps > 0)
        #expect(abs(snapshot.fps * snapshot.frameMS - 1000) < 0.001)
    }
}
