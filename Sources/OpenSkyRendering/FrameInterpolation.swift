// MetalFX frame interpolation: one extra frame between every two real frames, so the
// display shows twice the real frame rate. It runs after the temporal upscaler and reuses
// its depth and motion. See docs/rendering/frame-interpolation.md.

import Metal
import MetalFX
import QuartzCore
import Synchronization

nonisolated public enum FrameInterpolationSupport {
    /// Why `device` can never interpolate frames; nil when it can.
    public static func unsupportedReason(_ device: MTLDevice?) -> String? {
        guard let device, MTLFXFrameInterpolatorDescriptor.supportsMetal4FX(device) else {
            return "This GPU has no MetalFX frame interpolator"
        }
        return nil
    }
}

/// The interpolator and its two output-size textures, owned by `UpscaleTargets`.
final class InterpolationTargets {
    let interpolator: any MTL4FXFrameInterpolator
    /// Last frame's scaler output; it swaps with the scaler's target each frame.
    var history: MTLTexture
    /// The frame between the last real frame and this one.
    let frame: MTLTexture
    /// False until one real frame has filled `history`.
    var historyValid = false

    var allocations: [MTLAllocation] {
        [history, frame]
    }

    init(interpolator: any MTL4FXFrameInterpolator, history: MTLTexture, frame: MTLTexture) {
        self.interpolator = interpolator
        self.history = history
        self.frame = frame
    }
}

/// The renderer's frame interpolation switch and counters.
public struct FrameInterpolationState {
    /// Off by default: the real frame shows later, so input lags more.
    public var enabled = false
    /// Frames the interpolator built since launch.
    public internal(set) var interpolatedFrames = 0
    /// Whether the last frame built an interpolated frame.
    public internal(set) var lastFrameInterpolated = false
    /// Seconds between the last two real frames; offscreen frames use the fixed step.
    var deltaTime: Float = 1 / 30
    var lastLiveFrameTime: CFTimeInterval?
    /// Smoothed seconds a real frame works, without waiting for a drawable. The frame
    /// interval would also count the waits that interpolation itself causes.
    var realFrameWork: CFTimeInterval?
    /// Seconds this frame waited for a free drawable.
    var drawableWait: CFTimeInterval = 0
    /// Set while real frames are too slow to pace; the frame shows without interpolation.
    var pacingPause: String?
    /// Set when MetalFX refused the interpolator; cleared by switching it again.
    var creationFailure: String?
    /// The offscreen target of the interpolated frame, for tests and the benchmark.
    public internal(set) var offscreenFrame: MTLTexture?
    let latency = PresentLatencyInbox()
}

nonisolated enum FrameInterpolationPacing {
    /// Weight of the newest real frame interval in the smoothed one.
    static let smoothing = 0.1

    static func smoothed(_ previous: CFTimeInterval?, adding sample: CFTimeInterval)
        -> CFTimeInterval
    {
        guard let previous else { return sample }
        return previous + (sample - previous) * smoothing
    }

    /// Whether real frames are too slow to pace: each pair of images holds two display
    /// intervals, so a real frame must finish in two. Resuming needs a margin, because a
    /// paused frame skips the interpolator's own cost.
    static func shouldPause(
        realFrameWork: CFTimeInterval, displayInterval: CFTimeInterval, paused: Bool
    ) -> Bool {
        let budget = 2 * displayInterval
        return realFrameWork > budget * (paused ? 0.8 : 1.05)
    }

    static func pauseReason(realFrameWork: CFTimeInterval, displayInterval: CFTimeInterval)
        -> String
    {
        String(
            format: "Paused: real frames take %.0f ms, interpolation needs under %.0f ms",
            realFrameWork * 1000, 2 * displayInterval * 1000
        )
    }
}

/// What frame interpolation did; the rendering performance readout reads it.
nonisolated public struct FrameInterpolationStatus: Equatable, Sendable {
    public var enabled = false
    /// Why it cannot run now; nil while it runs or is off.
    public var unavailableReason: String?
    public var interpolatedFrames = 0
    /// Real frames per second, from the frame statistics.
    public var realFPS: Double = 0
    /// Average time from the start of a real frame to its present on screen.
    public var presentLatencyMS: Double?
    public var pacing: PresentPacing?

    public init(
        enabled: Bool = false,
        unavailableReason: String? = nil, interpolatedFrames: Int = 0, realFPS: Double = 0,
        presentLatencyMS: Double? = nil, pacing: PresentPacing? = nil
    ) {
        self.enabled = enabled
        self.unavailableReason = unavailableReason
        self.interpolatedFrames = interpolatedFrames
        self.realFPS = realFPS
        self.presentLatencyMS = presentLatencyMS
        self.pacing = pacing
    }

    public var isRunning: Bool {
        enabled && unavailableReason == nil
    }

    /// Each real frame shows twice while it runs: once interpolated, once real.
    public var shownFPS: Double {
        isRunning ? realFPS * 2 : realFPS
    }
}

/// How evenly the drawables showed: the gaps between two presents on screen.
nonisolated public struct PresentPacing: Equatable, Sendable {
    public var averageGapMS: Double
    public var longestGapMS: Double
    /// Gaps over 1.5 times the median gap: an image that stayed on screen too long.
    public var hitches: Int

    /// Nil without a gap. `gapsMS` are in present order.
    public init?(gapsMS: [Double]) {
        guard !gapsMS.isEmpty else { return nil }
        let median = gapsMS.sorted()[gapsMS.count / 2]
        averageGapMS = gapsMS.reduce(0, +) / Double(gapsMS.count)
        longestGapMS = gapsMS.max() ?? 0
        hitches = gapsMS.count { $0 > median * 1.5 }
    }
}

/// What the presented handlers measured since the last read.
nonisolated struct PresentWindow: Equatable {
    /// Average time from the start of a real frame to its present on screen.
    var latencyMS: Double?
    var pacing: PresentPacing?
}

/// Present times reported on a Core Animation thread; the main actor reads the averages.
nonisolated final class PresentLatencyInbox: Sendable {
    private struct Window {
        var totalSeconds: Double = 0
        var frames = 0
        var lastShown: CFTimeInterval?
        var gapsMS: [Double] = []
        var last = PresentWindow()
    }

    /// Bounds the gaps kept between two reads.
    private static let maxGaps = 1024
    private let pending = Mutex(Window())

    /// Host times in seconds. A drawable that never showed reports a present time of 0.
    func record(frameStart: CFTimeInterval, presented: CFTimeInterval) {
        guard presented > frameStart else { return }
        pending.withLock { window in
            window.totalSeconds += presented - frameStart
            window.frames += 1
        }
    }

    /// Every drawable that showed, real or interpolated, in present order.
    func recordShown(_ presented: CFTimeInterval) {
        guard presented > 0 else { return }
        pending.withLock { window in
            if let last = window.lastShown, presented > last, window.gapsMS.count < Self.maxGaps {
                window.gapsMS.append((presented - last) * 1000)
            }
            window.lastShown = presented
        }
    }

    /// The window since the last call; a part without new presents keeps its last value.
    func take() -> PresentWindow {
        pending.withLock { window in
            if window.frames > 0 {
                window.last.latencyMS = window.totalSeconds / Double(window.frames) * 1000
            }
            if let pacing = PresentPacing(gapsMS: window.gapsMS) {
                window.last.pacing = pacing
            }
            window.totalSeconds = 0
            window.frames = 0
            window.gapsMS.removeAll(keepingCapacity: true)
            return window.last
        }
    }
}
