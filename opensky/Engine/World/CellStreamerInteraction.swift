// View-ray target state and use-key action dispatch (M8.4.1). Split from
// CellStreamer so streaming scheduling remains below strict type/file limits.

import simd

extension CellStreamer {
    func sampleTerrain(at position: SIMD2<Float>) -> TerrainGroundSample? {
        guard interiorScene == nil else { return nil }
        return composition.sampleTerrain(at: position)
    }

    /// Water-surface height for the locomotion bridge's swim test (issue #188).
    /// Interiors report none: a vanilla interior authors its water as placed
    /// geometry rather than as the cell-wide plane XCLW describes.
    func sampleWaterHeight(at position: SIMD2<Float>) -> Float? {
        guard interiorScene == nil else { return nil }
        return composition.sampleWaterHeight(at: position)
    }

    /// Every collision candidate overlapping `bounds`: the immutable per-cell
    /// geometry plus the simulated bodies at their current pose (issue #193).
    ///
    /// A dynamic body is deliberately not a second kind of thing here. It hands
    /// over ordinary placed shapes, so the player capsule collides with a crate,
    /// the interaction ray targets it, and a shape sweep stops on it, all
    /// through the query they already ran. The static half comes first so the
    /// world a body cannot move stays ahead of it in every deterministic
    /// tie-break.
    func collisionCandidates(
        overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        staticCollisionCandidates(overlapping: bounds)
            + dynamicBodies.placedShapes(overlapping: bounds)
    }

    /// The immutable half alone, which is what the dynamic solver collides its
    /// bodies against — a body must not be handed itself as an obstacle.
    func staticCollisionCandidates(
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

    /// FULL name of a resident reference, or nil when nothing loaded names it.
    ///
    /// The journal's alias substitution reads this (issue #184): a `<Alias=...>`
    /// tag stands for the display name of whatever fills the alias, and an
    /// interaction is the only place a placed reference's resolved name is
    /// already sitting.
    func interactionName(reference: FormID) -> String? {
        activeInteraction(reference: reference)?.name
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

    /// The resident ACHR closest to `position`, or nil when none is loaded.
    ///
    /// Exists so the equipment sidebar can name an NPC without the user
    /// knowing a FormID (issue #178): the player has no rendered body this
    /// milestone, so "equip on the nearest actor" is what makes an equip
    /// visible. Linear over resident actors, which is tens of records, and
    /// deterministic on ties through `actorEntries()`.
    func nearestActorEntry(to position: SIMD3<Float>) -> RuntimeReferenceEntry? {
        residentActorEntries().min { lhs, rhs in
            distanceSquared(lhs, position) < distanceSquared(rhs, position)
        }
    }

    /// Every resident ACHR, deterministically ordered (issue #194).
    ///
    /// The set actor-value regeneration advances: an actor in a cell that is
    /// not loaded is not simulated at all in this engine, so regenerating one
    /// would be work nobody can observe. An interior scene replaces the
    /// exterior composition entirely, exactly as it does for every other lookup
    /// here.
    func residentActorEntries() -> [RuntimeReferenceEntry] {
        interiorScene.map {
            $0.references.sortedEntries().filter { $0.placedActor != nil }
        } ?? composition.actorEntries()
    }

    /// Snapshot index for live package-condition evaluation. Unlike the actor
    /// list, this includes disabled REFRs that an explicit run-on may name.
    func residentReferenceIndex() -> RuntimeReferenceIndex {
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

    /// Every resident container the merchant menu can be pointed at (issue
    /// #179). An interior scene replaces the exterior composition entirely, so
    /// it answers alone when present, exactly as it does for the lookups above.
    func containerInteractions() -> [PlacedInteraction] {
        if let interiorScene {
            return interiorScene.interactions.values
                .filter { $0.action == .search }
                .sorted { $0.reference.rawValue < $1.reference.rawValue }
        }
        return composition.containerInteractions()
    }

    /// The appearance skips the last build of the resident cells reported for
    /// one ACHR (issue #180).
    ///
    /// Matched on the "ACHR <id>: " prefix the builder writes, because the
    /// summary keeps these as readable lines rather than as a per-actor map:
    /// a cell holds a handful of actors and a rebuild rewrites the whole list,
    /// so an index would be a second thing to keep in step for no gain. Empty
    /// both when the actor resolved cleanly and when its cell is not resident;
    /// the panel distinguishes those by whether the actor was found at all.
    func appearanceSkipReasons(forActor formID: FormID) -> [String] {
        let prefix = "ACHR \(formID): "
        let summaries = interiorScene.map { [$0.summary] } ?? composition.actorSummaries()
        return summaries
            .flatMap(\.actorAppearanceSkipReasons)
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
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
