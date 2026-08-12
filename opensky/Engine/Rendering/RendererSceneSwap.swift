// Scene swap and GPU ring management, split out of Renderer.swift for the
// strict-lint file cap. The renderer's draw-side rings are sized to whatever it
// draws in one frame, which since issue #189 is the streamed scene plus the
// player body, so the two sizing callers live together here.

import Metal
import OpenSkyShaderTypes
import simd

// MARK: - Scene swap (cell streaming)

extension Renderer {
    /// Replaces the drawable scene between frames; optional `camera` reseeds
    /// sun/ambient and the free-fly pose (a first real scene after an empty
    /// launch scene needs a framing pose).
    ///
    /// Threading: must run on the thread that drives draw(in:) /
    /// renderOffscreen — the main thread. The renderer has no internal locking;
    /// "between frames" is guaranteed by that shared thread. The GPU may still
    /// be executing frames that reference the OLD scene: those resources go on
    /// the retire list instead of being released here — never blocks the GPU.
    func setScene(_ newScene: RenderScene, camera newCamera: SceneCamera? = nil) throws {
        purgeRetiredResources()
        // Allocate every fallible buffer before mutating live state; a failure
        // leaves the old scene + rings intact. The player body draws from the
        // same rings and survives the swap, so its groups are part of the size
        // the new rings have to cover (issue #189).
        let newDraw = try regrownDrawRing(
            for: newScene.drawCount + (playerBody?.render.drawCount ?? 0)
                + (playerFirstPersonRig?.render.drawCount ?? 0)
        )
        let newInstance = try regrownInstanceRing(
            for: newScene.instanceCount + (playerBody?.render.instanceCount ?? 0)
                + (playerFirstPersonRig?.render.instanceCount ?? 0)
        )
        // Old scene allocations retire as a whole; anything the new scene
        // shares is filtered out at purge time (live-set check), not here.
        var retiring = scene.residencyAllocations
        scene = newScene
        if let newCamera {
            camera = newCamera
            reseedMovement(camera: newCamera)
        }
        if let newDraw {
            adoptDrawRing(newDraw, retiring: &retiring)
        }
        if let newInstance {
            adoptInstanceRing(newInstance, retiring: &retiring)
        }
        residencySet.addAllocations(newScene.residencyAllocations)
        residencySet.commit()
        // Frames < frameIndex are committed; the newest (frameIndex - 1) is the
        // last that can reference the old resources.
        retired.append(RetiredAllocations(
            lastFrameIndex: UInt64(frameIndex - 1),
            allocations: retiring
        ))
    }

    /// Grows the rings to cover a frame that draws `drawCount` groups and
    /// `instanceCount` instances, doing nothing when they already fit. The
    /// player body calls this on attach: the scene it is drawn beside was sized
    /// without it (issue #189).
    func growRings(drawCount: Int, instanceCount: Int) throws {
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
    struct DrawRingRegrow {
        let draw: MTLBuffer
        let pointLight: MTLBuffer
        let shadowDraw: MTLBuffer
        let capacity: Int
    }

    /// Replacement instance-side rings (scene + shadow), sized to the new
    /// instance count. nil when the current rings already fit.
    struct InstanceRingRegrow {
        let instance: MTLBuffer
        let shadowInstance: MTLBuffer
        let capacity: Int
    }

    func regrownDrawRing(for drawCount: Int) throws -> DrawRingRegrow? {
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

    func regrownInstanceRing(for instanceCount: Int) throws -> InstanceRingRegrow? {
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
    func adoptDrawRing(_ ring: DrawRingRegrow, retiring: inout [MTLAllocation]) {
        retiring.append(drawUniformBuffer)
        retiring.append(pointLightBuffer)
        retiring.append(shadowDrawUniformBuffer)
        drawUniformBuffer = ring.draw
        pointLightBuffer = ring.pointLight
        shadowDrawUniformBuffer = ring.shadowDraw
        drawUniformSlotCapacity = ring.capacity
        residencySet.addAllocations([ring.draw, ring.pointLight, ring.shadowDraw])
    }

    func adoptInstanceRing(_ ring: InstanceRingRegrow, retiring: inout [MTLAllocation]) {
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
    func retireAllocations(_ allocations: [MTLAllocation]) {
        guard !allocations.isEmpty else { return }
        retired.append(RetiredAllocations(
            lastFrameIndex: UInt64(frameIndex - 1),
            allocations: allocations
        ))
    }

    /// Drops retire-list entries whose frames provably drained
    /// (endFrameEvent.signaledValue >= tag), removing their allocations from
    /// the residency set. MTLResidencySet membership is a plain set — removals
    /// take effect at commit() even if queued frames still reference the
    /// allocation — so removal waits for the drain proof, and must skip
    /// anything the CURRENT scene or rings also use (swap A -> B -> A, or
    /// adjacent cells sharing meshes: the allocation is both retired and live).
    /// Called opportunistically from draw(in:) and setScene.
    func purgeRetiredResources() {
        guard !retired.isEmpty else { return }
        let drained = endFrameEvent.signaledValue
        var ready: [MTLAllocation] = []
        retired.removeAll { entry in
            guard entry.lastFrameIndex <= drained else { return false }
            ready.append(contentsOf: entry.allocations)
            return true
        }
        guard !ready.isEmpty else { return }
        var live = Set(scene.residencyAllocations.map(ObjectIdentifier.init))
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
