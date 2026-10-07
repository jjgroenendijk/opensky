// Builds the interpolated frame after the temporal scaler and shows it before the real
// frame, half a real frame earlier. See docs/rendering/frame-interpolation.md.

import Metal
import MetalFX
import MetalKit
import QuartzCore

/// The second drawable of a live frame and the pass that draws into it.
struct InterpolatedDrawable {
    let drawable: CAMetalDrawable
    let descriptor: MTL4RenderPassDescriptor
}

extension Renderer {
    /// MTKView's own default, restored when interpolation stops.
    static let liveFramesPerSecond = 60

    public var frameInterpolationEnabled: Bool {
        get { upscale.interpolation.enabled }
        set {
            guard newValue != upscale.interpolation.enabled else { return }
            upscale.interpolation.enabled = newValue
            upscale.interpolation.creationFailure = nil
            upscale.resetPending = true
        }
    }

    /// Why interpolation cannot run now; nil while it runs or is off.
    public var frameInterpolationUnavailableReason: String? {
        guard upscale.interpolation.enabled else { return nil }
        if
            let reason = upscale.resources.interpolatorUnavailableReason
            ?? upscale.interpolation.creationFailure
        {
            return reason
        }
        guard upscale.renderScale.isOn, upscale.upscaler == .temporal else {
            return "Needs the temporal upscaler: pick a render scale"
        }
        return upscale.unavailableReason
    }

    public var isFrameInterpolationRunning: Bool {
        upscale.interpolation.enabled && frameInterpolationUnavailableReason == nil
    }

    /// Whether new upscale targets should carry an interpolator.
    var wantsFrameInterpolation: Bool {
        upscale.interpolation.enabled && upscale.upscaler == .temporal
            && upscale.resources.interpolatorUnavailableReason == nil
            && upscale.interpolation.creationFailure == nil
    }

    public var frameInterpolationStatus: FrameInterpolationStatus {
        FrameInterpolationStatus(
            enabled: upscale.interpolation.enabled,
            unsupportedReason: upscale.resources.interpolatorUnavailableReason,
            unavailableReason: frameInterpolationUnavailableReason,
            interpolatedFrames: upscale.interpolation.interpolatedFrames,
            realFPS: frameStats.snapshot().fps,
            presentLatencyMS: upscale.interpolation.latency.averageMS()
        )
    }

    /// Runs the interpolator on this frame's scaler output and draws the result, with the
    /// SWF and UI layers on top, into the interpolated target. False when no encoder.
    func encodeInterpolatedFrame(
        _ frame: UpscaleFrame, sceneDepth: MTLTexture, state: ScenePassState, frameOffset: Int
    ) -> Bool {
        guard
            let target = frame.interpolatedTarget,
            let interpolation = frame.targets.interpolation,
            let motion = frame.targets.motion
        else { return true }
        let interpolator = interpolation.interpolator
        let input = frame.targets.inputSize
        let output = frame.targets.outputSize
        interpolator.colorTexture = frame.targets.output
        interpolator.prevColorTexture = interpolation.history
        interpolator.depthTexture = sceneDepth
        interpolator.motionTexture = motion
        interpolator.outputTexture = interpolation.frame
        // The same motion and jitter conventions as the scaler (docs/rendering/upscaling.md).
        interpolator.motionVectorScaleX = Float(input.x)
        interpolator.motionVectorScaleY = Float(input.y)
        interpolator.jitterOffsetX = frame.jitter.x
        interpolator.jitterOffsetY = frame.jitter.y
        interpolator.isDepthReversed = false
        interpolator.deltaTime = upscale.interpolation.deltaTime
        interpolator.nearPlane = Self.nearPlane
        interpolator.farPlane = Self.farPlane
        interpolator.fieldOfView = activeFOVYRadians * 180 / .pi
        interpolator.aspectRatio = Float(output.x) / Float(output.y)
        interpolator.shouldResetHistory = frame.reset || !interpolation.historyValid
        interpolator.encode(commandBuffer: commandBuffer)
        guard
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: Self.upscaleCompositeDescriptor(target)
            )
        else { return false }
        encoder.label = "Interpolated Frame"
        encodeComposite(interpolation.frame, encoder: encoder, frameOffset: frameOffset)
        // The overlays draw again, sharp, instead of being interpolated.
        var overlay = ScenePassState(encoder: encoder, slot: state.slot, frustum: state.frustum)
        encodeSWF(descriptor: target, state: &overlay)
        encodeUI(descriptor: target, state: &overlay)
        encoder.endEncoding()
        upscale.interpolation.interpolatedFrames += 1
        upscale.interpolation.lastFrameInterpolated = true
        return true
    }

    /// A second drawable for this live frame; nil while interpolation does not run.
    func interpolatedDrawable(
        layer: CAMetalLayer, matching target: MTL4RenderPassDescriptor
    ) -> InterpolatedDrawable? {
        guard isFrameInterpolationRunning, let drawable = layer.nextDrawable() else { return nil }
        return InterpolatedDrawable(
            drawable: drawable,
            descriptor: Self.passDescriptor(color: drawable.texture, matching: target)
        )
    }

    /// The offscreen target of the interpolated frame; nil while interpolation does not run.
    func offscreenInterpolatedTarget(
        matching target: MTL4RenderPassDescriptor
    ) -> MTL4RenderPassDescriptor? {
        guard isFrameInterpolationRunning, let color = target.colorAttachments[0].texture
        else { return nil }
        if
            let frame = upscale.interpolation.offscreenFrame,
            frame.width == color.width, frame.height == color.height
        {
            return Self.passDescriptor(color: frame, matching: target)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: color.pixelFormat, width: color.width, height: color.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let frame = device.makeTexture(descriptor: descriptor) else { return nil }
        frame.label = "OffscreenInterpolatedFrame"
        if let old = upscale.interpolation.offscreenFrame {
            retireAllocations([old])
        }
        upscale.interpolation.offscreenFrame = frame
        residencySet.addAllocation(frame)
        residencySet.commit()
        return Self.passDescriptor(color: frame, matching: target)
    }

    private static func passDescriptor(
        color: MTLTexture, matching target: MTL4RenderPassDescriptor
    ) -> MTL4RenderPassDescriptor {
        let descriptor = MTL4RenderPassDescriptor()
        descriptor.colorAttachments[0].texture = color
        descriptor.depthAttachment.texture = target.depthAttachment.texture
        descriptor.stencilAttachment.texture = target.stencilAttachment.texture
        return descriptor
    }

    /// Halves the real frame rate while interpolation runs, so the shown rate matches the
    /// display, and records the time since the last real frame.
    func paceLiveFrame(view: MTKView, now: CFTimeInterval) {
        let refresh = view.window?.screen?.maximumFramesPerSecond ?? Self.liveFramesPerSecond
        let wanted = isFrameInterpolationRunning ? max(refresh / 2, 1) : Self.liveFramesPerSecond
        if view.preferredFramesPerSecond != wanted {
            view.preferredFramesPerSecond = wanted
        }
        if let last = upscale.interpolation.lastLiveFrameTime {
            upscale.interpolation.deltaTime = Float(min(max(now - last, 1.0 / 240), 0.25))
        }
        upscale.interpolation.lastLiveFrameTime = now
    }

    /// Shows the interpolated frame first, then the real one a display interval later.
    func present(
        _ drawable: CAMetalDrawable, interpolated: InterpolatedDrawable?, view: MTKView,
        frameStart: CFTimeInterval
    ) {
        let latency = upscale.interpolation.latency
        drawable.addPresentedHandler { shown in
            latency.record(frameStart: frameStart, presented: shown.presentedTime)
        }
        guard let interpolated, upscale.interpolation.lastFrameInterpolated else {
            drawable.present()
            return
        }
        let refresh = view.window?.screen?.maximumFramesPerSecond ?? Self.liveFramesPerSecond
        let interval = 1 / CFTimeInterval(max(refresh, 1))
        interpolated.drawable.present(afterMinimumDuration: interval)
        drawable.present(afterMinimumDuration: interval)
    }
}
