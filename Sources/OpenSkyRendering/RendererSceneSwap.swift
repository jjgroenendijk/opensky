// Scene swap and GPU ring management. The rings cover the streamed scene plus the
// player body, so both sizing callers live here.

import Metal
import OpenSkyShaderTypes
import simd

// MARK: - Scene swap (cell streaming)

extension Renderer {
    /// Replaces the scene between frames; `camera` reseeds sun, ambient and the fly pose.
    /// Main thread only. In-flight frames may use the old scene, so its resources go on
    /// the retire list; the GPU is never blocked.
    public func setScene(_ newScene: RenderScene, camera newCamera: SceneCamera? = nil) throws {
        purgeRetiredResources()
        // Allocate every fallible buffer first, so a failure keeps the old scene. The new
        // rings must also cover the player body.
        let newDraw = try regrownDrawRing(
            for: newScene.drawCount + rigDrawCount + effects.scene.drawCount
        )
        let newInstance = try regrownInstanceRing(
            for: newScene.instanceCount + rigInstanceCount + effects.scene.instanceCount
        )
        // Old scene allocations retire as a whole; anything the new scene
        // shares is filtered out at purge time (live-set check), not here.
        var retiring = sceneAllocations
        scene = newScene
        if let newCamera {
            camera = newCamera
            frameDriver?.didReplaceCamera(newCamera)
        }
        if let newDraw {
            adoptDrawRing(newDraw, retiring: &retiring)
        }
        if let newInstance {
            adoptInstanceRing(newInstance, retiring: &retiring)
        }
        residencySet.addAllocations(sceneAllocations)
        residencySet.commit()
        // Frames < frameIndex are committed; the newest (frameIndex - 1) is the
        // last that can reference the old resources.
        retired.append(RetiredAllocations(
            lastFrameIndex: UInt64(frameIndex - 1),
            allocations: retiring
        ))
    }

    /// Grows the rings to fit `drawCount` groups and `instanceCount` instances. The
    /// player body calls it on attach, because the scene was sized without it.
    public func growRings(drawCount: Int, instanceCount: Int) throws {
        let newDraw = try regrownDrawRing(for: drawCount)
        let newInstance = try regrownInstanceRing(for: instanceCount)
        guard newDraw != nil || newInstance != nil else { return }
        var retiring: [MTLAllocation] = []
        if let newDraw {
            adoptDrawRing(newDraw, retiring: &retiring)
        }
        if let newInstance {
            adoptInstanceRing(newInstance, retiring: &retiring)
        }
        residencySet.commit()
        retireAllocations(retiring)
    }

    /// Replacement draw-side rings (draw + point-light + shadow-draw), sized to
    /// the new draw count. nil when the current rings already fit.
    public struct DrawRingRegrow {
        public let draw: MTLBuffer
        public let pointLight: MTLBuffer
        public let shadowDraw: MTLBuffer
        public let capacity: Int
    }

    /// Replacement instance-side rings (scene + shadow), sized to the new
    /// instance count. nil when the current rings already fit.
    public struct InstanceRingRegrow {
        public let instance: MTLBuffer
        public let shadowInstance: MTLBuffer
        public let capacity: Int
    }

    public func regrownDrawRing(for drawCount: Int) throws -> DrawRingRegrow? {
        guard drawCount > drawUniformSlotCapacity else { return nil }
        let capacity = Self.slotCapacity(for: drawCount)
        return try DrawRingRegrow(
            draw: Self.makeUniformBuffer(
                device: device,
                length: Self.alignedDrawUniformsSize * capacity * Self.maxFramesInFlight,
                label: "DrawUniforms"
            ),
            pointLight: Self.makeUniformBuffer(
                device: device,
                length: MemoryLayout<PointLightUniform>.stride
                    * LightingConstant.maxPointLights.rawValue
                    * capacity * Self.maxFramesInFlight,
                label: "PointLights"
            ),
            shadowDraw: Self.makeUniformBuffer(
                device: device,
                length: Self.alignedDrawUniformsSize
                    * Self.shadowDrawCapacity(capacity) * Self.maxFramesInFlight,
                label: "ShadowDrawUniforms"
            ),
            capacity: capacity
        )
    }

    public func regrownInstanceRing(for instanceCount: Int) throws -> InstanceRingRegrow? {
        guard instanceCount > instanceSlotCapacity else { return nil }
        let capacity = Self.slotCapacity(for: instanceCount)
        let length = MemoryLayout<InstanceTransform>.stride * capacity * Self.maxFramesInFlight
        return try InstanceRingRegrow(
            instance: Self.makeUniformBuffer(
                device: device, length: length, label: "InstanceTransforms"
            ),
            // Per-cascade caster runs need cascadeCount x the scene ring
            // (matches makeSceneRings sizing).
            shadowInstance: Self.makeUniformBuffer(
                device: device,
                length: length * ShadowConstant.cascadeCount.rawValue,
                label: "ShadowInstanceTransforms"
            ),
            capacity: capacity
        )
    }

    /// Swaps in the new draw-side rings, retiring the old ones (they may back
    /// in-flight frames) and adding the new ones to the residency set.
    public func adoptDrawRing(_ ring: DrawRingRegrow, retiring: inout [MTLAllocation]) {
        retiring.append(drawUniformBuffer)
        retiring.append(pointLightBuffer)
        retiring.append(shadowDrawUniformBuffer)
        drawUniformBuffer = ring.draw
        pointLightBuffer = ring.pointLight
        shadowDrawUniformBuffer = ring.shadowDraw
        drawUniformSlotCapacity = ring.capacity
        residencySet.addAllocations([ring.draw, ring.pointLight, ring.shadowDraw])
    }

    public func adoptInstanceRing(_ ring: InstanceRingRegrow, retiring: inout [MTLAllocation]) {
        retiring.append(instanceTransformBuffer)
        retiring.append(shadowInstanceBuffer)
        instanceTransformBuffer = ring.instance
        shadowInstanceBuffer = ring.shadowInstance
        instanceSlotCapacity = ring.capacity
        residencySet.addAllocations([ring.instance, ring.shadowInstance])
    }

    /// Queues allocations for deferred residency-set removal once the frames
    /// that may still reference them provably drain (used by setSWFMovie;
    /// setScene manages its own retire entry alongside the ring swap).
    public func retireAllocations(_ allocations: [MTLAllocation]) {
        guard !allocations.isEmpty else { return }
        retired.append(RetiredAllocations(
            lastFrameIndex: UInt64(frameIndex - 1),
            allocations: allocations
        ))
    }

    /// Drops retire-list entries whose frames drained (`signaledValue >= tag`) from the
    /// residency set, skipping anything the current scene or rings still use. Called
    /// from draw(in:) and setScene.
    public func purgeRetiredResources() {
        guard !retired.isEmpty else { return }
        let drained = endFrameEvent.signaledValue
        var ready: [MTLAllocation] = []
        retired.removeAll { entry in
            guard entry.lastFrameIndex <= drained else { return false }
            ready.append(contentsOf: entry.allocations)
            return true
        }
        guard !ready.isEmpty else { return }
        var live = Set(sceneAllocations.map(ObjectIdentifier.init))
        live.formUnion(effects.scene.residencyAllocations.map(ObjectIdentifier.init))
        live
            .formUnion((effects.loadingCover?.residencyAllocations ?? [])
                .map(ObjectIdentifier.init))
        live.insert(ObjectIdentifier(frameUniformBuffer))
        live.insert(ObjectIdentifier(drawUniformBuffer))
        live.insert(ObjectIdentifier(pointLightBuffer))
        live.insert(ObjectIdentifier(instanceTransformBuffer))
        live.insert(ObjectIdentifier(shadowDrawUniformBuffer))
        live.insert(ObjectIdentifier(shadowInstanceBuffer))
        live.insert(ObjectIdentifier(shadow.map))
        if let movie = swf.movie {
            live.formUnion(movie.residencyAllocations.map(ObjectIdentifier.init))
        }
        live.formUnion((gpuCull.scene?.allocations ?? []).map(ObjectIdentifier.init))
        // A drained A entry may share an allocation with undrained B. Keep that
        // allocation resident until every retired frame using it drains.
        for entry in retired {
            live.formUnion(entry.allocations.map(ObjectIdentifier.init))
        }
        var seen = Set<ObjectIdentifier>()
        let removable = ready.filter { allocation in
            let id = ObjectIdentifier(allocation)
            return !live.contains(id) && seen.insert(id).inserted
        }
        guard !removable.isEmpty else { return }
        residencySet.removeAllocations(removable)
        residencySet.commit()
    }
}
