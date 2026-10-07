// Motion vectors for the temporal upscaler. A fullscreen pass reprojects each pixel's
// depth with last frame's camera. A second pass redraws the moving groups (skinned
// meshes and references a body moves) with last frame's matrices and bones, where they
// are the visible surface. See docs/rendering/upscaling.md.

import Metal
import OpenSkyShaderTypes
import simd

extension Renderer {
    /// Writes this frame's motion uniforms and returns their GPU address.
    func writeMotionUniforms(_ frame: UpscaleFrame, slot: Int) -> UInt64 {
        var uniforms = UpscaleMotionUniforms(
            inverseJitteredViewProjection: frame.jitteredViewProjection.inverse,
            viewProjection: frame.viewProjection,
            previousViewProjection: frame.reset
                ? frame.viewProjection : upscale.previousViewProjection ?? frame.viewProjection,
            nearDepthLimit: areFirstPersonArmsVisible ? FirstPersonCamera.depthSlice : 0,
            padding0: 0, padding1: 0, padding2: 0
        )
        let buffer = upscale.resources.uniformBuffer
        let offset = UpscaleResources.uniformStride * slot
        buffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<UpscaleMotionUniforms>.size)
        return buffer.gpuAddress + UInt64(offset)
    }

    func encodeCameraMotion(_ frame: UpscaleFrame, sceneDepth: MTLTexture, uniforms: UInt64)
        -> Bool
    {
        let descriptor = MTL4RenderPassDescriptor()
        descriptor.colorAttachments[0].texture = frame.targets.motion
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }
        encoder.label = "Camera Motion"
        encoder.barrier(
            afterQueueStages: .fragment, beforeStages: .fragment, visibilityOptions: .device
        )
        encoder.setArgumentTable(argumentTable, stages: [.vertex, .fragment])
        argumentTable.setAddress(uniforms, index: BufferIndex.motionUniforms.rawValue)
        argumentTable.setTexture(sceneDepth.gpuResourceID, index: TextureIndex.diffuse.rawValue)
        encoder.setRenderPipelineState(upscale.resources.cameraMotion)
        encoder.setCullMode(.none)
        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        endMotionEncoder(encoder)
        return true
    }

    /// Redraws the moving groups into the motion target. Their matrices this frame
    /// become next frame's previous ones.
    func encodeObjectMotion(
        _ frame: UpscaleFrame,
        sceneDepth: MTLTexture,
        state: ScenePassState,
        uniforms: UInt64
    ) -> Bool {
        let groups = upscale.objectMotionEnabled
            ? (opaqueDrawGroups + alphaTestedDrawGroups).filter(\.isMoving) : []
        var models: [MotionKey: float4x4] = [:]
        defer { upscale.previousModels = models }
        let count = groups.reduce(0) { $0 + $1.instances.count }
        guard count > 0, let instances = motionInstanceRing(count: count, slot: state.slot)
        else { return true }
        guard
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: Self.objectMotionDescriptor(frame, sceneDepth: sceneDepth)
            )
        else { return false }
        encoder.label = "Object Motion"
        encoder.barrier(
            afterQueueStages: .fragment, beforeStages: .fragment, visibilityOptions: .device
        )
        encoder.setArgumentTable(argumentTable, stages: [.vertex, .fragment])
        encoder.setDepthStencilState(upscale.resources.motionDepthState)
        encoder.setFrontFacing(.counterClockwise)
        argumentTable.setAddress(uniforms, index: BufferIndex.motionUniforms.rawValue)
        var cursor = 0
        for group in groups {
            let first = cursor
            for (index, placed) in group.instances.enumerated() {
                let current = drawn(placed).modelMatrix
                let key = MotionKey(
                    mesh: ObjectIdentifier(group.mesh),
                    instance: placed.referenceFormID != 0 ? placed.referenceFormID : UInt32(index)
                )
                let previous = frame.reset ? current : upscale.previousModels[key] ?? current
                models[key] = current
                instances.write(MotionInstance(current: current, previous: previous), at: cursor)
                cursor += 1
            }
            drawMotion(
                group,
                instances: instances.address(at: first),
                encoder: encoder,
                slot: state.slot
            )
        }
        endMotionEncoder(encoder)
        return true
    }

    private func drawMotion(
        _ group: DrawGroup,
        instances: UInt64,
        encoder: MTL4RenderCommandEncoder,
        slot: Int
    ) {
        let skinned = group.mesh.isSkinned
        encoder.setRenderPipelineState(
            skinned ? upscale.resources.skinnedMotion : upscale.resources.staticMotion
        )
        argumentTable.setAddress(
            group.mesh.vertexBuffer.gpuAddress, index: BufferIndex.vertices.rawValue
        )
        argumentTable.setAddress(instances, index: BufferIndex.motionInstances.rawValue)
        if skinned {
            bindMotionBones(group.mesh, slot: slot)
        }
        encoder.setCullMode(group.material.doubleSided ? .none : .back)
        encoder.drawInstances(
            of: group.mesh, .packed(count: group.instances.count, address: instances)
        )
    }

    /// This frame's palette and last frame's. A mesh that was not drawn last frame has
    /// no palette there, so it uses this frame's and shows no skin motion.
    private func bindMotionBones(_ mesh: RenderMesh, slot: Int) {
        guard let skinning = mesh.skinningBuffer, let bones = mesh.boneMatrixBuffer else {
            return
        }
        prepareBoneMatricesOnce(for: mesh, slot: slot)
        let previousSlot = upscale.previousBonePrepared.contains(ObjectIdentifier(mesh))
            ? (slot + Self.maxFramesInFlight - 1) % Self.maxFramesInFlight : slot
        argumentTable.setAddress(
            skinning.gpuAddress, index: BufferIndex.skinningAttributes.rawValue
        )
        argumentTable.setAddress(
            bones.gpuAddress + UInt64(mesh.boneMatrixOffset(slot: slot)),
            index: BufferIndex.boneMatrices.rawValue
        )
        argumentTable.setAddress(
            bones.gpuAddress + UInt64(mesh.boneMatrixOffset(slot: previousSlot)),
            index: BufferIndex.previousBoneMatrices.rawValue
        )
    }

    /// The last motion encoder hands its writes to the scaler's encoders.
    private func endMotionEncoder(_ encoder: MTL4RenderCommandEncoder) {
        encoder.barrier(
            afterStages: .fragment, beforeQueueStages: Self.upscaleStages,
            visibilityOptions: .device
        )
        encoder.endEncoding()
    }

    private static func objectMotionDescriptor(
        _ frame: UpscaleFrame,
        sceneDepth: MTLTexture
    ) -> MTL4RenderPassDescriptor {
        let descriptor = MTL4RenderPassDescriptor()
        descriptor.colorAttachments[0].texture = frame.targets.motion
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.depthAttachment.texture = sceneDepth
        descriptor.depthAttachment.loadAction = .load
        descriptor.depthAttachment.storeAction = .store
        descriptor.stencilAttachment.texture = sceneDepth
        descriptor.stencilAttachment.loadAction = .dontCare
        descriptor.stencilAttachment.storeAction = .dontCare
        return descriptor
    }

    /// This slot's run of the motion instance ring, grown to fit `count`.
    private func motionInstanceRing(count: Int, slot: Int) -> MotionInstanceRun? {
        if count > upscale.motionInstanceCapacity {
            let capacity = Self.slotCapacity(for: count)
            guard
                let buffer = try? Self.makeUniformBuffer(
                    device: device,
                    length: MemoryLayout<MotionInstance>.stride * capacity * Self.maxFramesInFlight,
                    label: "MotionInstances"
                )
            else { return nil }
            if let old = upscale.motionInstances {
                retireAllocations([old])
            }
            upscale.motionInstances = buffer
            upscale.motionInstanceCapacity = capacity
            residencySet.addAllocation(buffer)
            residencySet.commit()
        }
        guard let buffer = upscale.motionInstances else { return nil }
        return MotionInstanceRun(buffer: buffer, base: slot * upscale.motionInstanceCapacity)
    }
}

/// One frame slot's part of the motion instance ring.
struct MotionInstanceRun {
    let buffer: MTLBuffer
    let base: Int

    func write(_ instance: MotionInstance, at index: Int) {
        var value = instance
        buffer.contents().advanced(by: (base + index) * MemoryLayout<MotionInstance>.stride)
            .copyMemory(from: &value, byteCount: MemoryLayout<MotionInstance>.size)
    }

    func address(at index: Int) -> UInt64 {
        buffer.gpuAddress + UInt64((base + index) * MemoryLayout<MotionInstance>.stride)
    }
}

nonisolated extension DrawGroup {
    /// Skinned meshes animate and a body moves its references, so their pixels move
    /// apart from the camera.
    var isMoving: Bool {
        mesh.isSkinned || instances.contains { $0.referenceFormID != 0 }
    }
}
