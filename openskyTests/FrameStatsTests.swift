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
        #expect(line.contains("gpu avg"))
        // Synthetic GPU ticks were provided, so the GPU figure is a number,
        // not the n/a placeholder.
        #expect(!line.contains("n/a"))
    }
}
