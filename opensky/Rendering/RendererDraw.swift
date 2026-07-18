// MTKView delegate loop. Scene-pass encoding lives in RendererScenePass;
// setup + resource lifetime live in Renderer and RendererSetup.

import MetalKit
import QuartzCore

extension Renderer: MTKViewDelegate {
    func mtkView(_: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = MatrixMath.perspective(
            fovYRadians: MatrixMath.radians(fromDegrees: 65),
            aspectRatio: aspect,
            nearZ: Self.nearPlane,
            farZ: Self.farPlane
        )
    }

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let passDescriptor = view.currentMTL4RenderPassDescriptor,
            let metalLayer = view.layer as? CAMetalLayer
        else { return }

        let cpuStart = frameStats.beginFrame()
        advanceCamera()
        // Streaming may setScene synchronously before this frame encodes.
        onFrame?(freeFlyCamera.position)
        purgeRetiredResources()

        endFrameEvent.wait(
            untilSignaledValue: UInt64(frameIndex - Self.maxFramesInFlight),
            timeoutMS: 10
        )

        let slot = frameIndex % Self.maxFramesInFlight
        let gpuTicks = resolveTimestamps(slot: slot)
        let allocator = commandAllocators[slot]
        allocator.reset()
        commandBuffer.beginCommandBuffer(allocator: allocator)
        if let heap = timestampHeap {
            commandBuffer.writeTimestamp(counterHeap: heap, index: slot * 2)
        }

        let encoded = encodeScenePass(
            descriptor: passDescriptor,
            slot: slot,
            projection: projectionMatrix
        )
        guard encoded else {
            commandBuffer.endCommandBuffer()
            return
        }

        if let heap = timestampHeap {
            commandBuffer.writeTimestamp(counterHeap: heap, index: slot * 2 + 1)
        }
        commandBuffer.useResidencySet(metalLayer.residencySet)
        commandBuffer.endCommandBuffer()

        commandQueue.waitForDrawable(drawable)
        commandQueue.commit([commandBuffer])
        commandQueue.signalDrawable(drawable)
        commandQueue.signalEvent(endFrameEvent, value: UInt64(frameIndex))
        frameIndex += 1
        drawable.present()
        frameStats.endFrame(cpuStartNS: cpuStart, gpuTicks: gpuTicks)
    }
}
