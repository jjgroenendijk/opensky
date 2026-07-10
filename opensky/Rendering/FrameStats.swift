// CPU + GPU frame statistics (todo 2.6): rolling window, one log line per
// window — the measurable basis for the milestone 2.9 ">30 fps sustained"
// gate; never judged by eye. CPU side times the encode work and the
// frame-to-frame interval; GPU side consumes MTL4 counter-heap timestamp
// ticks, converted to wall time via MTLDevice.sampleTimestamps correlation
// pairs taken at window boundaries (GPU ticks are not nanoseconds).

import Foundation
import Metal
import os

nonisolated final class FrameStats {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "FrameStats"
    )
    private static let signposter = OSSignposter(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "FrameStats"
    )
    /// Frames per log window (~2 s at 60 fps).
    private static let windowSize = 120

    private let device: MTLDevice
    /// (CPU ns, GPU ticks) pair from the previous window boundary.
    private var correlation: (cpu: MTLTimestamp, gpu: MTLTimestamp)

    private var frameCount = 0
    private var encodeTotalNS: UInt64 = 0
    private var intervalTotalNS: UInt64 = 0
    private var intervalMaxNS: UInt64 = 0
    private var intervalCount = 0
    private var lastFrameEndNS: UInt64?
    private var gpuTotalTicks: UInt64 = 0
    private var gpuFrameCount = 0
    private var signpostState: OSSignpostIntervalState?

    init(device: MTLDevice) {
        self.device = device
        correlation = Self.sample(device: device)
    }

    private static func sample(device: MTLDevice) -> (cpu: MTLTimestamp, gpu: MTLTimestamp) {
        let sample = device.sampleTimestamps()
        return (sample.cpu, sample.gpu)
    }

    /// Call at the top of the render callback; pass the result to endFrame.
    func beginFrame() -> UInt64 {
        signpostState = Self.signposter.beginInterval("frame")
        return DispatchTime.now().uptimeNanoseconds
    }

    /// Call after commit. `gpuTicks` is the resolved counter-heap pair of an
    /// earlier completed frame (nil while the pipeline fills or when the
    /// heap is unavailable). Returns the logged summary line when this frame
    /// closed a stats window — surfaced so tests can verify the instrument.
    @discardableResult
    func endFrame(cpuStartNS: UInt64, gpuTicks: (start: UInt64, end: UInt64)?) -> String? {
        if let state = signpostState {
            Self.signposter.endInterval("frame", state)
            signpostState = nil
        }
        let now = DispatchTime.now().uptimeNanoseconds
        encodeTotalNS += now - cpuStartNS
        if let last = lastFrameEndNS {
            let interval = now - last
            intervalTotalNS += interval
            intervalMaxNS = max(intervalMaxNS, interval)
            intervalCount += 1
        }
        lastFrameEndNS = now
        if let gpuTicks, gpuTicks.end > gpuTicks.start {
            gpuTotalTicks += gpuTicks.end - gpuTicks.start
            gpuFrameCount += 1
        }
        frameCount += 1
        if frameCount >= Self.windowSize {
            return flush()
        }
        return nil
    }

    private func flush() -> String? {
        let next = Self.sample(device: device)
        defer {
            correlation = next
            frameCount = 0
            encodeTotalNS = 0
            intervalTotalNS = 0
            intervalMaxNS = 0
            intervalCount = 0
            gpuTotalTicks = 0
            gpuFrameCount = 0
        }

        let encodeMS = Double(encodeTotalNS) / Double(frameCount) / 1e6
        guard intervalCount > 0 else { return nil }
        let intervalMS = Double(intervalTotalNS) / Double(intervalCount) / 1e6
        let maxMS = Double(intervalMaxNS) / 1e6
        let fps = intervalMS > 0 ? 1000 / intervalMS : 0

        var gpuText = "n/a"
        // Ticks -> ns scale from how far both clocks moved over the window.
        if gpuFrameCount > 0, next.gpu > correlation.gpu, next.cpu > correlation.cpu {
            let scale = Double(next.cpu - correlation.cpu) / Double(next.gpu - correlation.gpu)
            let gpuMS = Double(gpuTotalTicks) / Double(gpuFrameCount) * scale / 1e6
            gpuText = String(format: "%.2f", gpuMS)
        }

        let summary = String(
            format: "frame avg %.2f ms (%.0f fps, max %.2f ms) | "
                + "cpu encode avg %.2f ms | gpu avg %@ ms",
            intervalMS, fps, maxMS, encodeMS, gpuText
        )
        // .notice persists to the log store (`log show`); .info is
        // memory-only and invisible after the fact — this line is the 2.9
        // fps measurement, it must be retrievable.
        Self.logger.notice("\(summary, privacy: .public)")
        return summary
    }
}
