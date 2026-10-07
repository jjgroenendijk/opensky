// MTKView delegate loop. Scene-pass encoding lives in RendererScenePass;
// setup + resource lifetime live in Renderer and RendererSetup.

import MetalKit
import QuartzCore

extension Renderer: MTKViewDelegate {
    public func mtkView(_: MTKView, drawableSizeWillChange size: CGSize) {
        guard size.height > 0 else { return }
        drawableAspectRatio = Float(size.width) / Float(size.height)
        rebuildProjection()
    }

    public func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let passDescriptor = view.currentMTL4RenderPassDescriptor,
            let metalLayer = view.layer as? CAMetalLayer
        else { return }

        let cpuStart = frameStats.beginFrame()
        wallClock.beginFrame()
        // Camera, the per-frame hook (streaming may setScene synchronously
        // before this frame encodes), game clock, world simulation, weather.
        frameDriver?.prepareLiveFrame()
        let particleDelta = updateAnimationsFromWallClock()
        updateParticles(deltaTime: particleDelta)
        updatePrecipitation(deltaTime: particleDelta)
        // Audio.
        frameDriver?.finishLiveFrame()
        purgeRetiredResources()

        endFrameEvent.wait(
            untilSignaledValue: UInt64(frameIndex - Self.maxFramesInFlight),
            timeoutMS: 10
        )

        let slot = frameIndex % Self.maxFramesInFlight
        let allocator = commandAllocators[slot]
        allocator.reset()
        commandBuffer.beginCommandBuffer(allocator: allocator)
        encodeTextureStreaming(target: passDescriptor)

        let encodeStart = DispatchTime.now().uptimeNanoseconds
        let shadowEncoded = encodeShadowPass(slot: slot, projection: projectionMatrix)
        let encoded = shadowEncoded && encodeScenePass(
            descriptor: passDescriptor,
            slot: slot,
            projection: projectionMatrix
        )
        lastEncodeMS = Double(DispatchTime.now().uptimeNanoseconds - encodeStart) / 1e6
        guard encoded else {
            commandBuffer.endCommandBuffer()
            return
        }

        encodeWindowCapture(of: drawable.texture)
        commandBuffer.useResidencySet(metalLayer.residencySet)
        commandBuffer.endCommandBuffer()

        commandQueue.waitForDrawable(drawable)
        commitFrame()
        commandQueue.signalDrawable(drawable)
        commandQueue.signalEvent(endFrameEvent, value: UInt64(frameIndex))
        frameIndex += 1
        drawable.present()
        frameStats.endFrame(cpuStartNS: cpuStart)
    }
}
