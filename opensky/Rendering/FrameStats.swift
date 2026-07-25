// CPU + GPU frame statistics (todo 2.6): rolling window, one log line per
// window — the measurable basis for the milestone 2.9 ">30 fps sustained"
// gate; never judged by eye. CPU side times the encode work and the
// frame-to-frame interval; GPU side consumes MTL4 counter-heap timestamp
// ticks, converted to wall time via MTLDevice.sampleTimestamps correlation
// pairs taken at window boundaries (GPU ticks are not nanoseconds).
// A second, shorter window runs in parallel purely to feed live readouts
// (`snapshot()`); it accumulates the same measurements on its own cadence and
// never touches the 120-frame window's state.

import Foundation
import Metal
import os

/// Latest completed short-window reading, for live readouts (the World panel
/// and the frame HUD both poll this so they can never show different numbers).
/// Separate from the 120-frame log window, which stays the milestone 2.9
/// measurement and is never disturbed by a reader.
nonisolated struct FrameStatsSnapshot: Equatable {
    /// Frames per second implied by `frameMS`; zero before the first window.
    let fps: Double
    /// Average frame-to-frame interval in milliseconds.
    let frameMS: Double
    /// Worst frame-to-frame interval in the window, in milliseconds.
    let maxFrameMS: Double
    /// Average CPU encode time in milliseconds.
    let encodeMS: Double
    /// Average GPU time in milliseconds, or nil while no counter-heap pair has
    /// resolved yet (the readout shows "n/a", matching the log line).
    let gpuMS: Double?
    /// Frames that fed this reading; zero means "no window has closed yet".
    let sampleCount: Int

    /// Reported before the first short window closes, and by providers with no
    /// live renderer.
    static let empty = FrameStatsSnapshot(
        fps: 0, frameMS: 0, maxFrameMS: 0, encodeMS: 0, gpuMS: nil, sampleCount: 0
    )

    /// True once a window has closed, so a readout can distinguish "measuring"
    /// from "genuinely zero frames per second".
    var hasMeasurement: Bool {
        sampleCount > 0
    }
}

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
    /// Frames per live-readout window (~0.5 s at 60 fps). Short enough that a
    /// 2 Hz poll always sees a fresh reading, long enough that the number does
    /// not jitter between polls.
    private static let liveWindowSize = 30

    private let device: MTLDevice
    /// (CPU ns, GPU ticks) pair from the previous window boundary.
    private var correlation: (cpu: MTLTimestamp, gpu: MTLTimestamp)
    /// The live window's own correlation pair. Deliberately separate from
    /// `correlation`: sampling for a readout must not move the boundary the
    /// 120-frame GPU average is computed against.
    private var liveCorrelation: (cpu: MTLTimestamp, gpu: MTLTimestamp)
    private var live = LiveWindow()
    /// The only state read from outside the render callback. Everything else in
    /// this class is confined to the thread that calls beginFrame/endFrame (the
    /// MTKView draw callback), so "safe to call snapshot() at 2 Hz from the main
    /// thread" means exactly this: readers touch one small value behind an
    /// unfair lock, and never observe a half-updated accumulator.
    private let published = OSAllocatedUnfairLock(initialState: FrameStatsSnapshot.empty)

    /// Live-window accumulators, mirroring the log window's but reset on their
    /// own cadence.
    private struct LiveWindow {
        var frameCount = 0
        var encodeTotalNS: UInt64 = 0
        var intervalTotalNS: UInt64 = 0
        var intervalMaxNS: UInt64 = 0
        var intervalCount = 0
        var gpuTotalTicks: UInt64 = 0
        var gpuFrameCount = 0
    }

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
        liveCorrelation = correlation
    }

    /// Current live reading. Safe from any thread, including while frames are
    /// being recorded — see `published`.
    func snapshot() -> FrameStatsSnapshot {
        published.withLock { $0 }
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
        let interval = lastFrameEndNS.map { now - $0 }
        if let interval {
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
        recordLive(encodeNS: now - cpuStartNS, interval: interval, gpuTicks: gpuTicks)
        if frameCount >= Self.windowSize {
            return flush()
        }
        return nil
    }

    /// Feeds the live window from the same measurements the log window used, so
    /// the readout and the log line can only ever differ by window length.
    private func recordLive(
        encodeNS: UInt64,
        interval: UInt64?,
        gpuTicks: (start: UInt64, end: UInt64)?
    ) {
        live.encodeTotalNS += encodeNS
        if let interval {
            live.intervalTotalNS += interval
            live.intervalMaxNS = max(live.intervalMaxNS, interval)
            live.intervalCount += 1
        }
        if let gpuTicks, gpuTicks.end > gpuTicks.start {
            live.gpuTotalTicks += gpuTicks.end - gpuTicks.start
            live.gpuFrameCount += 1
        }
        live.frameCount += 1
        guard live.frameCount >= Self.liveWindowSize else { return }
        publishLiveWindow()
    }

    private func publishLiveWindow() {
        let next = Self.sample(device: device)
        defer {
            liveCorrelation = next
            live = LiveWindow()
        }
        guard live.intervalCount > 0 else { return }
        let frameMS = Double(live.intervalTotalNS) / Double(live.intervalCount) / 1e6
        var gpuMS: Double?
        if live.gpuFrameCount > 0, next.gpu > liveCorrelation.gpu, next.cpu > liveCorrelation.cpu {
            let scale = Double(next.cpu - liveCorrelation.cpu)
                / Double(next.gpu - liveCorrelation.gpu)
            gpuMS = Double(live.gpuTotalTicks) / Double(live.gpuFrameCount) * scale / 1e6
        }
        let snapshot = FrameStatsSnapshot(
            fps: frameMS > 0 ? 1000 / frameMS : 0,
            frameMS: frameMS,
            maxFrameMS: Double(live.intervalMaxNS) / 1e6,
            encodeMS: Double(live.encodeTotalNS) / Double(live.frameCount) / 1e6,
            gpuMS: gpuMS,
            sampleCount: live.frameCount
        )
        published.withLock { $0 = snapshot }
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
