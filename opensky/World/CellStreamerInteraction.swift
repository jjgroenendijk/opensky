// View-ray target state and use-key action dispatch (M8.4.1). Split from
// CellStreamer so streaming scheduling remains below strict type/file limits.

import simd

extension CellStreamer {
    func sampleTerrain(at position: SIMD2<Float>) -> TerrainGroundSample? {
        guard interiorScene == nil else { return nil }
        return composition.sampleTerrain(at: position)
    }

    func collisionCandidates(
        overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        if let interiorScene {
            return interiorScene.staticCollision.candidates(overlapping: bounds)
        }
        return composition.collisionCandidates(overlapping: bounds)
    }

    func updateInteractionTarget(ray: InteractionRay?) {
        let target = ray.flatMap { ray -> InteractionTarget? in
            let shapes = collisionCandidates(overlapping: ray.bounds)
            guard
                let hit = InteractionRaycaster.nearestHit(ray: ray, shapes: shapes),
                let interaction = activeInteraction(reference: hit.reference)
            else { return nil }
            return InteractionTarget(
                interaction: interaction,
                hitPosition: hit.position,
                distance: hit.distance
            )
        }
        guard target != interactionTarget else { return }
        interactionTarget = target
        onInteractionTargetChanged?(target)
    }

    private func activeInteraction(reference: FormID) -> PlacedInteraction? {
        if let interiorScene {
            return interiorScene.interactions[reference]
        }
        return composition.interaction(reference: reference)
    }

    /// Full decoded record behind a reference the player is looking at or
    /// otherwise addressing (issue #158). An interior scene replaces the
    /// exterior composition entirely, so it answers alone when present.
    func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        if let interiorScene {
            return interiorScene.references.entry(for: formID)
        }
        return composition.referenceEntry(formID: formID)
    }

    func referenceEntry(key: ReferenceKey) -> RuntimeReferenceEntry? {
        if let interiorScene {
            return interiorScene.references[key]
        }
        return composition.referenceEntry(key: key)
    }

    /// Which resident cell holds a reference, so a Papyrus world write can be
    /// attributed to one cell instead of every resident one (issue #172).
    func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        if let interiorScene {
            return interiorScene.references[key] == nil ? nil : interiorScene.location
        }
        return composition.cellLocation(of: key)
    }

    func activateInteractionTarget() {
        guard let interactionTarget else { return }
        onInteraction(InteractionEvent(target: interactionTarget))
        guard interactionTarget.interaction.action == .open else { return }
        guard
            requestDoorTransition(activeDoor(reference: interactionTarget.interaction.reference))
        else { return }
        doorMotionInteraction = interactionTarget.interaction
        onInteractionAnimation?(InteractionAnimationEvent(
            interaction: interactionTarget.interaction,
            phase: .motionStarted
        ))
    }

    private func activeDoor(reference: FormID) -> PlacedDoor? {
        if let interiorScene {
            return interiorScene.doors.first { $0.reference == reference }
        }
        return composition.door(reference: reference)
    }
}

/// The streamer is the app's answer to "what does this reference decode to,
/// and where is it right now" for the Papyrus world bridge (issue #172). The
/// three members it needs already existed; the conformance only names them.
extension CellStreamer: PapyrusWorldReferenceSource {}
