// CPU and GPU frame statistics over a rolling 120-frame window, one log line each; the
// measured basis for frame-rate gates. GPU time is the span Metal's commit feedback
// reports for each frame's commit. A shorter parallel window feeds `snapshot()` for live
// readouts.

import Foundation
import OpenSkyFormatsCore
import os
import Synchronization

/// Latest completed short-window reading, for live readouts (the World panel
/// and the frame HUD both poll this so they can never show different numbers).
/// Separate from the 120-frame log window, which stays the milestone 2.9
/// measurement and is never disturbed by a reader.
nonisolated public struct FrameStatsSnapshot: Equatable, Sendable {
    /// Frames per second implied by `frameMS`; zero before the first window.
    public let fps: Double
    /// Average frame-to-frame interval in milliseconds.
    public let frameMS: Double
    /// Worst frame-to-frame interval in the window, in milliseconds.
    public let maxFrameMS: Double
    /// Average CPU encode time in milliseconds.
    public let encodeMS: Double
    /// Average GPU time in milliseconds, or nil while no commit feedback has
    /// arrived yet (the readout shows "n/a", matching the log line).
    public let gpuMS: Double?
    /// Frames that fed this reading; zero means "no window has closed yet".
    public let sampleCount: Int

    /// Reported before the first short window closes, and by providers with no
    /// live renderer.
    public static let empty = FrameStatsSnapshot(
        fps: 0, frameMS: 0, maxFrameMS: 0, encodeMS: 0, gpuMS: nil, sampleCount: 0
    )

    /// True once a window has closed, so a readout can distinguish "measuring"
    /// from "genuinely zero frames per second".
    public var hasMeasurement: Bool {
        sampleCount > 0
    }
}

/// GPU spans reported by Metal's commit feedback, which runs on a Metal thread.
/// `FrameStats.endFrame` takes them on the render thread.
nonisolated public final class GPUSpanInbox: Sendable {
    private let pending = Mutex<(totalNS: UInt64, count: Int)>((0, 0))

    public init() {}

    /// Host times in seconds, as `MTL4CommitFeedback` reports them.
    public func record(start: CFTimeInterval, end: CFTimeInterval) {
        guard end > start else { return }
        let nanoseconds = UInt64(((end - start) * 1e9).rounded())
        pending.withLock { $0 = ($0.totalNS + nanoseconds, $0.count + 1) }
    }

    func take() -> (totalNS: UInt64, count: Int) {
        pending.withLock { value in
            defer { value = (0, 0) }
            return value
        }
    }
}

nonisolated public final class FrameStats {
    private static let logger = EngineLogger(
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

    public let gpuSpans = GPUSpanInbox()
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
        var gpuTotalNS: UInt64 = 0
        var gpuFrameCount = 0
    }

    private var frameCount = 0
    private var encodeTotalNS: UInt64 = 0
    private var intervalTotalNS: UInt64 = 0
    private var intervalMaxNS: UInt64 = 0
    private var intervalCount = 0
    private var lastFrameEndNS: UInt64?
    private var gpuTotalNS: UInt64 = 0
    private var gpuFrameCount = 0
    private var signpostState: OSSignpostIntervalState?

    public init() {}

    /// Current live reading. Safe from any thread, including while frames are
    /// being recorded — see `published`.
    public func snapshot() -> FrameStatsSnapshot {
        published.withLock { $0 }
    }

    /// Call at the top of the render callback; pass the result to endFrame.
    public func beginFrame() -> UInt64 {
        signpostState = Self.signposter.beginInterval("frame")
        return DispatchTime.now().uptimeNanoseconds
    }

    /// Call after commit. GPU time comes from the spans that reached `gpuSpans`
    /// since the last call. Returns the logged summary line when this frame
    /// closed a stats window, so tests can check the instrument.
    @discardableResult
    public func endFrame(cpuStartNS: UInt64) -> String? {
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
        let gpu = gpuSpans.take()
        gpuTotalNS += gpu.totalNS
        gpuFrameCount += gpu.count
        frameCount += 1
        recordLive(encodeNS: now - cpuStartNS, interval: interval, gpu: gpu)
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
        gpu: (totalNS: UInt64, count: Int)
    ) {
        live.encodeTotalNS += encodeNS
        if let interval {
            live.intervalTotalNS += interval
            live.intervalMaxNS = max(live.intervalMaxNS, interval)
            live.intervalCount += 1
        }
        live.gpuTotalNS += gpu.totalNS
        live.gpuFrameCount += gpu.count
        live.frameCount += 1
        guard live.frameCount >= Self.liveWindowSize else { return }
        publishLiveWindow()
    }

    private func publishLiveWindow() {
        defer { live = LiveWindow() }
        guard live.intervalCount > 0 else { return }
        let frameMS = Double(live.intervalTotalNS) / Double(live.intervalCount) / 1e6
        let gpuMS = Self.averageMS(live.gpuTotalNS, count: live.gpuFrameCount)
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
        defer {
            frameCount = 0
            encodeTotalNS = 0
            intervalTotalNS = 0
            intervalMaxNS = 0
            intervalCount = 0
            gpuTotalNS = 0
            gpuFrameCount = 0
        }

        let encodeMS = Double(encodeTotalNS) / Double(frameCount) / 1e6
        guard intervalCount > 0 else { return nil }
        let intervalMS = Double(intervalTotalNS) / Double(intervalCount) / 1e6
        let maxMS = Double(intervalMaxNS) / 1e6
        let fps = intervalMS > 0 ? 1000 / intervalMS : 0

        let gpuText = Self.averageMS(gpuTotalNS, count: gpuFrameCount)
            .map { String(format: "%.2f", $0) } ?? "n/a"

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

    private static func averageMS(_ totalNS: UInt64, count: Int) -> Double? {
        count > 0 ? Double(totalNS) / Double(count) / 1e6 : nil
    }
}
