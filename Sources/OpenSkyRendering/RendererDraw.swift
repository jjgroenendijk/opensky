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

    /// Camera, the per-frame hook (streaming may set a scene before this frame encodes),
    /// game clock, world simulation, weather, then audio.
    private func advanceLiveFrame() {
        wallClock.beginFrame()
        adoptFrameInput(frameDriver?.prepareLiveFrame() ?? frameInput)
        let particleDelta = updateAnimationsFromWallClock()
        updateParticles(deltaTime: particleDelta)
        updatePrecipitation(deltaTime: particleDelta)
        frameDriver?.finishLiveFrame()
        purgeRetiredResources()
    }

    public func draw(in view: MTKView) {
        guard let metalLayer = view.layer as? CAMetalLayer else { return }

        let cpuStart = frameStats.beginFrame()
        let frameStart = CACurrentMediaTime()
        paceLiveFrame(view: view, now: frameStart)
        advanceLiveFrame()

        // Taken after the simulation: a drawable still on screen frees up meanwhile.
        let drawableWait = CACurrentMediaTime()
        let drawable = view.currentDrawable
        upscale.interpolation.drawableWait += CACurrentMediaTime() - drawableWait
        guard let drawable, let passDescriptor = view.currentMTL4RenderPassDescriptor else {
            frameStats.endFrame(cpuStartNS: cpuStart)
            return
        }

        endFrameEvent.wait(
            untilSignaledValue: UInt64(frameIndex - Self.maxFramesInFlight),
            timeoutMS: 10
        )

        let slot = frameIndex % Self.maxFramesInFlight
        beginFrameCapture()
        let allocator = commandAllocators[slot]
        allocator.reset()
        commandBuffer.beginCommandBuffer(allocator: allocator)
        passTimer?.beginFrame(
            slot: slot, frame: frameIndex, completedFrame: Int(endFrameEvent.signaledValue),
            commandBuffer: commandBuffer
        )
        refreshFrameDrawGroups()
        encodeTextureStreaming(target: passDescriptor)
        encodeRayTracedShadows()
        passTimer?.mark(.setup, commandBuffer: commandBuffer)
        let interpolated = interpolatedDrawable(layer: metalLayer, matching: passDescriptor)

        let encodeStart = DispatchTime.now().uptimeNanoseconds
        let shadowEncoded = encodeShadowPass(slot: slot, projection: projectionMatrix)
        passTimer?.mark(.shadows, commandBuffer: commandBuffer)
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
        passTimer?.mark(.scene, commandBuffer: commandBuffer)
        guard encoded else {
            commandBuffer.endCommandBuffer()
            finishFailedFrame(afterEarlyCommit: shadowEncoded)
            return
        }

        encodeWindowCapture(of: drawable.texture)
        commandBuffer.useResidencySet(metalLayer.residencySet)
        commandBuffer.endCommandBuffer()

        commitLiveFrame(drawable, interpolated: interpolated)
        endFrameCapture()
        present(drawable, interpolated: interpolated, view: view, frameStart: frameStart)
        frameStats.endFrame(cpuStartNS: cpuStart)
    }

    private func commitLiveFrame(_ drawable: CAMetalDrawable, interpolated: InterpolatedDrawable?) {
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
    }
}
