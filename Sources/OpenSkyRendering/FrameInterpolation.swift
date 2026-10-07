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

    static func interpolator(
        input: SIMD2<Int>, output: SIMD2<Int>, compiler: PipelineCache
    ) throws -> any MTL4FXFrameInterpolator {
        let descriptor = MTLFXFrameInterpolatorDescriptor()
        descriptor.colorTextureFormat = UpscaleResources.outputFormat
        descriptor.outputTextureFormat = UpscaleResources.outputFormat
        descriptor.depthTextureFormat = .depth32Float_stencil8
        descriptor.motionTextureFormat = UpscaleResources.motionFormat
        descriptor.inputWidth = input.x
        descriptor.inputHeight = input.y
        descriptor.outputWidth = output.x
        descriptor.outputHeight = output.y
        guard
            let interpolator = descriptor.makeFrameInterpolator(
                device: compiler.device, compiler: compiler.compiler
            )
        else { throw RendererError.upscalerUnavailable }
        return interpolator
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
    /// Set when MetalFX refused the interpolator; cleared by switching it again.
    var creationFailure: String?
    /// The offscreen target of the interpolated frame, for tests and the benchmark.
    public internal(set) var offscreenFrame: MTLTexture?
    let latency = PresentLatencyInbox()
}

/// What frame interpolation did; the Rendering Performance panel reads it.
nonisolated public struct FrameInterpolationStatus: Equatable, Sendable {
    public var enabled = false
    /// Why this GPU can never run it; the switch stays off and disabled.
    public var unsupportedReason: String?
    /// Why it cannot run now; nil while it runs or is off.
    public var unavailableReason: String?
    public var interpolatedFrames = 0
    /// Real frames per second, from the frame statistics.
    public var realFPS: Double = 0
    /// Average time from the start of a real frame to its present on screen.
    public var presentLatencyMS: Double?

    public init(
        enabled: Bool = false, unsupportedReason: String? = nil,
        unavailableReason: String? = nil, interpolatedFrames: Int = 0, realFPS: Double = 0,
        presentLatencyMS: Double? = nil
    ) {
        self.enabled = enabled
        self.unsupportedReason = unsupportedReason
        self.unavailableReason = unavailableReason
        self.interpolatedFrames = interpolatedFrames
        self.realFPS = realFPS
        self.presentLatencyMS = presentLatencyMS
    }

    public var isRunning: Bool {
        enabled && unavailableReason == nil
    }

    /// Each real frame shows twice while it runs: once interpolated, once real.
    public var shownFPS: Double {
        isRunning ? realFPS * 2 : realFPS
    }
}

/// Present times reported on a Core Animation thread; the main actor reads the average.
nonisolated final class PresentLatencyInbox: Sendable {
    private struct Window {
        var totalSeconds: Double = 0
        var frames = 0
        var lastAverageMS: Double?
    }

    private let pending = Mutex(Window())

    /// Host times in seconds. A drawable that never showed reports a present time of 0.
    func record(frameStart: CFTimeInterval, presented: CFTimeInterval) {
        guard presented > frameStart else { return }
        pending.withLock { window in
            window.totalSeconds += presented - frameStart
            window.frames += 1
        }
    }

    /// The average since the last call, or the previous average when no frame showed.
    func averageMS() -> Double? {
        pending.withLock { window in
            guard window.frames > 0 else { return window.lastAverageMS }
            let average = window.totalSeconds / Double(window.frames) * 1000
            window = Window(lastAverageMS: average)
            return average
        }
    }
}

nonisolated extension RenderPerformanceReadout {
    public static func frameInterpolationText(_ status: FrameInterpolationStatus) -> String {
        let latency = status.presentLatencyMS.map { String(format: "%.1f ms", $0) } ?? "n/a"
        let rates = String(
            format: "Real: %.0f fps  Shown: %.0f fps", status.realFPS, status.shownFPS
        )
        if let reason = status.unsupportedReason {
            return "Frame interpolation: unavailable\n\(reason)"
        }
        guard status.enabled else {
            return "Frame interpolation: off\n\(rates)\nInput to screen: \(latency)"
        }
        if let reason = status.unavailableReason {
            return "Frame interpolation: unavailable\n\(reason)"
        }
        return """
        Frame interpolation: on, \(status.interpolatedFrames) frames built
        \(rates)
        Input to screen: \(latency)
        """
    }
}
