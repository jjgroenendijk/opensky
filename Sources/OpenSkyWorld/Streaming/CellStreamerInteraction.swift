// View-ray target state and use-key action dispatch. Split from
// CellStreamer so streaming scheduling remains below strict type/file limits.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension CellStreamer {
    public func sampleTerrain(at position: SIMD2<Float>) -> TerrainGroundSample? {
        guard interiorScene == nil else { return nil }
        return composition.sampleTerrain(at: position)
    }

    /// Water-surface height for the locomotion bridge's swim test.
    /// Interiors report none: a vanilla interior authors its water as placed
    /// geometry rather than as the cell-wide plane XCLW describes.
    public func sampleWaterHeight(at position: SIMD2<Float>) -> Float? {
        guard interiorScene == nil else { return nil }
        return composition.sampleWaterHeight(at: position)
    }

    /// Every collision candidate overlapping `bounds`: the per-cell static geometry
    /// plus the simulated bodies at their current pose, as ordinary placed shapes.
    /// Static shapes come first, for deterministic tie-breaks.
    public func collisionCandidates(
        overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        staticCollisionCandidates(overlapping: bounds)
            + dynamicBodies.placedShapes(overlapping: bounds)
    }

    /// The immutable half alone, which is what the dynamic solver collides its
    /// bodies against — a body must not be handed itself as an obstacle.
    public func staticCollisionCandidates(
        overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        if let interiorScene {
            return interiorScene.staticCollision.candidates(overlapping: bounds)
        }
        return composition.collisionCandidates(overlapping: bounds)
    }

    public func updateInteractionTarget(ray: InteractionRay?) {
        let pick = ray.map(pickInteraction(ray:)) ?? (target: nil, speaker: nil)
        talk.speaker = pick.speaker
        guard pick.target != interactionTarget else { return }
        interactionTarget = pick.target
        onInteractionTargetChanged?(pick.target)
    }

    /// What one view ray points at: the nearest activatable object, or the nearest
    /// actor in front of it. The solid hit is the occluder test, so an actor behind
    /// a shut door is not a Talk target.
    private func pickInteraction(
        ray: InteractionRay
    ) -> (target: InteractionTarget?, speaker: ReferenceKey?) {
        let shapes = collisionCandidates(overlapping: ray.bounds)
        let hit = InteractionRaycaster.nearestHit(ray: ray, shapes: shapes)
        let solid = hit.flatMap { hit in
            activeInteraction(reference: hit.reference).map {
                InteractionTarget(
                    interaction: $0, hitPosition: hit.position, distance: hit.distance
                )
            }
        }
        guard
            let actor = TalkTargetPicker.nearest(
                ray: ray, candidates: talk.candidateSource?() ?? []
            ),
            actor.distance < (hit?.distance ?? .greatestFiniteMagnitude)
        else {
            return (solid, nil)
        }
        return (Self.talkTarget(actor), actor.candidate.key)
    }

    /// One picked actor as a crosshair target, so HUD prompt, compass and panel read it the
    /// usual way. No sounds: a greeting is voice, not the base record's activation sound.
    private static func talkTarget(_ hit: TalkHit) -> InteractionTarget {
        InteractionTarget(
            interaction: PlacedInteraction(
                reference: hit.candidate.reference,
                base: hit.candidate.base,
                position: hit.candidate.feet,
                name: hit.candidate.name,
                action: .talk,
                actionLabel: InteractionAction.talk.defaultLabel,
                sounds: nil
            ),
            hitPosition: hit.position,
            distance: hit.distance
        )
    }

    /// FULL name of a resident reference, or nil when nothing loaded names it.
    ///
    /// The journal's alias substitution reads this: a `<Alias=...>`
    /// tag stands for the display name of whatever fills the alias, and an
    /// interaction is the only place a placed reference's resolved name is
    /// already sitting.
    public func interactionName(reference: FormID) -> String? {
        activeInteraction(reference: reference)?.name
    }

    /// Every activatable reference in the loaded cells. An interior replaces the exterior.
    public var residentInteractions: [PlacedInteraction] {
        if let interiorScene {
            return Array(interiorScene.interactions.values)
        }
        return composition.cells.values.flatMap(\.interactions.values)
    }

    /// Every runtime reference in the loaded cells, in no fixed order.
    public var residentReferences: [RuntimeReferenceEntry] {
        if let interiorScene {
            return interiorScene.references.sortedEntries()
        }
        return composition.cells.values.flatMap { $0.references.sortedEntries() }
    }

    public func activateChildren(of key: ReferenceKey) -> [ReferenceKey] {
        guard let parent = referenceEntry(key: key) else { return [] }
        return residentReferences.activateChildren(of: parent.formID)
    }

    public func residentInteraction(reference: FormID) -> PlacedInteraction? {
        activeInteraction(reference: reference)
    }

    private func activeInteraction(reference: FormID) -> PlacedInteraction? {
        if let interiorScene {
            return interiorScene.interactions[reference]
        }
        return composition.interaction(reference: reference)
    }

    /// Full decoded record behind a reference the player is looking at or
    /// otherwise addressing. An interior scene replaces the
    /// exterior composition entirely, so it answers alone when present.
    public func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        if let interiorScene {
            return interiorScene.references.entry(for: formID)
        }
        return composition.referenceEntry(formID: formID)
    }

    public func referenceEntry(key: ReferenceKey) -> RuntimeReferenceEntry? {
        if let interiorScene {
            return interiorScene.references[key]
        }
        return composition.referenceEntry(key: key)
    }

    /// The resident ACHR closest to `position`, or nil when none is loaded. The
    /// equipment sidebar uses it. Linear over resident actors, with deterministic
    /// ties through `actorEntries()`.
    public func nearestActorEntry(to position: SIMD3<Float>) -> RuntimeReferenceEntry? {
        residentActorEntries().min { lhs, rhs in
            distanceSquared(lhs, position) < distanceSquared(rhs, position)
        }
    }

    /// Every resident ACHR, deterministically ordered: the set actor-value
    /// regeneration advances. An interior scene replaces the exterior composition.
    public func residentActorEntries() -> [RuntimeReferenceEntry] {
        interiorScene.map {
            $0.references.sortedEntries().filter { $0.placedActor != nil }
        } ?? composition.actorEntries()
    }

    /// The built scene for one resident cell, or nil. It gives a cell's `XOWN` owner
    /// and `XLCN` link. An interior scene replaces the exterior composition.
    public func residentScene(at location: CellSceneLocation) -> CellScene? {
        if let interiorScene {
            return interiorScene.location == location ? interiorScene : nil
        }
        return composition.cells.values.first { $0.location == location }
    }

    /// Snapshot index for live package-condition evaluation. Unlike the actor
    /// list, this includes disabled REFRs that an explicit run-on may name.
    public func residentReferenceIndex() -> RuntimeReferenceIndex {
        RuntimeReferenceIndex(entries: interiorScene.map {
            $0.references.sortedEntries()
        } ?? composition.referenceEntries())
    }

    private func distanceSquared(
        _ entry: RuntimeReferenceEntry,
        _ position: SIMD3<Float>
    ) -> Float {
        guard let actor = entry.placedActor else { return .greatestFiniteMagnitude }
        return simd_length_squared(actor.placement.position - position)
    }

    /// Every resident container the merchant menu can use. An interior scene answers
    /// alone when present.
    public func containerInteractions() -> [PlacedInteraction] {
        if let interiorScene {
            return interiorScene.interactions.values
                .filter { $0.action == .search }
                .sorted { $0.reference.rawValue < $1.reference.rawValue }
        }
        return composition.containerInteractions()
    }

    /// The appearance skips the last build reported for one ACHR, matched on the
    /// "ACHR <id>: " prefix. Empty when the actor resolved cleanly or is not
    /// resident; the panel tells those apart.
    public func appearanceSkipReasons(forActor formID: FormID) -> [String] {
        let prefix = "ACHR \(formID): "
        let summaries = interiorScene.map { [$0.summary] } ?? composition.actorSummaries()
        return summaries
            .flatMap(\.actorAppearanceSkipReasons)
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    /// Which resident cell holds a reference, so a Papyrus world write can be
    /// attributed to one cell instead of every resident one.
    public func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        if let interiorScene {
            return interiorScene.references[key] == nil ? nil : interiorScene.location
        }
        return composition.cellLocation(of: key)
    }

    public func activateInteractionTarget() {
        guard let interactionTarget else { return }
        activate(interactionTarget)
    }

    /// One activation of `target`: the gate first, then the event, talk, and door.
    /// The lockpicking menu calls this again after a lock opens.
    public func activate(_ target: InteractionTarget) {
        if let refusal = activationGate.gate?(target) {
            activationGate.refusals(ActivationRefusalEvent(target: target, refusal: refusal))
            return
        }
        onInteraction(InteractionEvent(target: target))
        // After the plain event, so an activated actor reaches the audio and
        // Papyrus subscribers in the same order an activated door does before
        // anything opens a menu on top of the world.
        if
            let event = TalkActivationEvent(
                interaction: target.interaction,
                pickedSpeaker: talk.speaker,
                placedKey: { referenceEntry(formID: target.interaction.reference)?.key }
            )
        {
            talk.activations(event)
        }
        guard target.interaction.action == .open else { return }
        guard requestDoorTransition(activeDoor(reference: target.interaction.reference))
        else { return }
        doorMotionInteraction = target.interaction
        onInteractionAnimation?(InteractionAnimationEvent(
            interaction: target.interaction,
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
/// and where is it right now" for the Papyrus world bridge. The
/// three members it needs already existed; the conformance only names them.
extension CellStreamer: PapyrusWorldReferenceSource {}
