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
        let frameStart = CACurrentMediaTime()
        paceLiveFrame(view: view, now: frameStart)
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
        refreshFrameDrawGroups()
        encodeTextureStreaming(target: passDescriptor)
        encodeRayTracedShadows()
        let interpolated = interpolatedDrawable(layer: metalLayer, matching: passDescriptor)

        let encodeStart = DispatchTime.now().uptimeNanoseconds
        let shadowEncoded = encodeShadowPass(slot: slot, projection: projectionMatrix)
        if shadowEncoded {
            commitEarlyFrameWork(allocator: allocator)
        }
        let encoded = shadowEncoded && encodeScenePass(
            descriptor: passDescriptor,
            slot: slot,
            projection: projectionMatrix,
            interpolatedTarget: interpolated?.descriptor
        )
        lastEncodeMS = Double(DispatchTime.now().uptimeNanoseconds - encodeStart) / 1e6
        guard encoded else {
            commandBuffer.endCommandBuffer()
            finishFailedFrame(afterEarlyCommit: shadowEncoded)
            return
        }

        encodeWindowCapture(of: drawable.texture)
        commandBuffer.useResidencySet(metalLayer.residencySet)
        commandBuffer.endCommandBuffer()

        commandQueue.waitForDrawable(drawable)
        if let interpolated {
            commandQueue.waitForDrawable(interpolated.drawable)
        }
        commitFrame()
        commandQueue.signalDrawable(drawable)
        if let interpolated {
            commandQueue.signalDrawable(interpolated.drawable)
        }
        commandQueue.signalEvent(endFrameEvent, value: UInt64(frameIndex))
        frameIndex += 1
        present(drawable, interpolated: interpolated, view: view, frameStart: frameStart)
        frameStats.endFrame(cpuStartNS: cpuStart)
    }
}
