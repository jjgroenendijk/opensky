// View-ray target state and use-key action dispatch. Split from
// CellStreamer so streaming scheduling remains below strict type/file limits.

import OpenSkyActorPresentation
public import OpenSkyCells
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

extension CellStreamer.ResidentSteps {
    public func updateInteractionTarget(ray: InteractionRay?) {
        let pick = ray.map(pickInteraction(ray:)) ?? (target: nil, speaker: nil)
        streamer.talk.speaker = pick.speaker
        guard pick.target != streamer.interactionTarget else { return }
        streamer.interactionTarget = pick.target
        streamer.events.onInteractionTargetChanged?(pick.target)
    }

    /// What one view ray points at: the nearest activatable object, or the nearest
    /// actor in front of it. The solid hit is the occluder test, so an actor behind
    /// a shut door is not a Talk target.
    private func pickInteraction(
        ray: InteractionRay
    ) -> (target: InteractionTarget?, speaker: ReferenceKey?) {
        let hit = streamer.collision.nearestCollisionHit(ray: ray)
        let solid = hit.flatMap { hit in
            activeInteraction(reference: hit.reference).flatMap {
                $0.automaticArea == nil ? $0 : nil
            }.map {
                InteractionTarget(
                    interaction: $0, hitPosition: hit.position, distance: hit.distance
                )
            }
        }
        guard
            let actor = TalkTargetPicker.nearest(
                ray: ray, candidates: streamer.talk.candidateSource?(ray) ?? []
            ),
            actor.distance < (hit?.distance ?? .greatestFiniteMagnitude)
        else {
            return (solid ?? streamer.transitions.nearestAutomaticDoor(to: ray.origin), nil)
        }
        return (Self.talkTarget(actor), actor.candidate.key)
    }

    /// One picked actor as a crosshair target, so HUD prompt, compass and readout read it the
    /// usual way. No sounds: a greeting is voice, not the base record's activation sound.
    private static func talkTarget(_ hit: TalkHit) -> InteractionTarget {
        InteractionTarget(
            interaction: PlacedInteraction(
                reference: hit.candidate.reference,
                base: hit.candidate.base,
                position: hit.candidate.feet,
                name: hit.candidate.name,
                action: .talk,
                actionLabel: hit.candidate.actionLabel ?? InteractionAction.talk.defaultLabel,
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
        if let interiorScene = streamer.interiorScene {
            return Array(interiorScene.interactions.values)
        }
        return streamer.composition.cells.values.flatMap(\.interactions.values)
    }

    /// Every runtime reference in the loaded cells, in no fixed order.
    public var residentReferences: [RuntimeReferenceEntry] {
        if let interiorScene = streamer.interiorScene {
            return interiorScene.references.sortedEntries()
        }
        return streamer.composition.cells.values.flatMap { $0.references.sortedEntries() }
    }

    public func activateChildren(of key: ReferenceKey) -> [ActivateChild] {
        guard let parent = referenceEntry(key: key) else { return [] }
        return residentReferences.activateChildren(of: parent.formID)
    }

    public func residentInteraction(reference: FormID) -> PlacedInteraction? {
        activeInteraction(reference: reference)
    }

    private func activeInteraction(reference: FormID) -> PlacedInteraction? {
        if let interiorScene = streamer.interiorScene {
            return interiorScene.interactions[reference]
        }
        return streamer.composition.interaction(reference: reference)
    }

    /// Full decoded record behind a reference the player is looking at or
    /// otherwise addressing. An interior scene replaces the
    /// exterior composition entirely, so it answers alone when present.
    public func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        if let interiorScene = streamer.interiorScene {
            return interiorScene.references.entry(for: formID)
        }
        return streamer.composition.referenceEntry(formID: formID)
    }

    public func referenceEntry(key: ReferenceKey) -> RuntimeReferenceEntry? {
        if let interiorScene = streamer.interiorScene {
            return interiorScene.references[key]
        }
        return streamer.composition.referenceEntry(key: key)
    }

    public func residentEntries() -> [RuntimeReferenceEntry] {
        streamer.interiorScene?.references.sortedEntries() ?? streamer.composition
            .referenceEntries()
    }

    public func pluginPlacement(of key: ReferenceKey) -> PluginPlacement? {
        guard
            let placedRecords = streamer.placedRecords, let entry = placedRecords.entry(for: key),
            let home = placedRecords.home(of: entry)
        else { return nil }
        return PluginPlacement(entry: entry, home: home)
    }

    /// One resident ACHR in constant time. An interior scene replaces the
    /// exterior composition.
    public func residentActorPlacement(key: ReferenceKey) -> ResidentActorPlacement? {
        if let interiorActorPlacements = streamer.interiorActorPlacements {
            return interiorActorPlacements[key]
        }
        return streamer.composition.actorPlacements[key]
    }

    /// One entry of `residentActorEntries()` in constant time.
    public func residentActorEntry(key: ReferenceKey) -> RuntimeReferenceEntry? {
        if let interiorScene = streamer.interiorScene {
            return streamer.interiorActorPlacements?[key] == nil ? nil : interiorScene
                .references[key]
        }
        return streamer.composition.actorEntry(key: key)
    }

    /// The resident ACHR closest to `position`, or nil when none is loaded. The
    /// equipment readout uses it. Linear over resident actors, with deterministic
    /// ties through `actorEntries()`.
    public func nearestActorEntry(to position: SIMD3<Float>) -> RuntimeReferenceEntry? {
        residentActorEntries().min { lhs, rhs in
            distanceSquared(lhs, position) < distanceSquared(rhs, position)
        }
    }

    /// Every resident ACHR, deterministically ordered: the set actor-value
    /// regeneration advances. An interior scene replaces the exterior composition.
    public func residentActorEntries() -> [RuntimeReferenceEntry] {
        streamer.interiorScene?.references.sortedActorEntries ?? streamer.composition.actorEntries()
    }

    /// Every resident cell's built scene: the interior alone, or the loaded exterior cells.
    public var residentScenes: [CellScene] {
        if let interiorScene = streamer.interiorScene {
            return [interiorScene]
        }
        return Array(streamer.composition.cells.values)
    }

    /// The built scene for one resident cell, or nil. It gives a cell's `XOWN` owner
    /// and `XLCN` link. An interior scene replaces the exterior composition.
    public func residentScene(at location: CellSceneLocation) -> CellScene? {
        if let interiorScene = streamer.interiorScene {
            return interiorScene.location == location ? interiorScene : nil
        }
        return streamer.composition.cells.values.first { $0.location == location }
    }

    /// Snapshot index for live package-condition evaluation. Unlike the actor
    /// list, this includes disabled REFRs that an explicit run-on may name.
    public func residentReferenceIndex() -> RuntimeReferenceIndex {
        streamer.interiorScene?.references ?? streamer.composition.mergedReferenceIndex()
    }

    private func distanceSquared(
        _ entry: RuntimeReferenceEntry,
        _ position: SIMD3<Float>
    ) -> Float {
        guard let actor = entry.placedActor else { return .greatestFiniteMagnitude }
        return simd_length_squared(actor.placement.position - position)
    }

    /// The appearance skips the last build reported for one ACHR, matched on the
    /// "ACHR <id>: " prefix. Empty when the actor resolved cleanly or is not
    /// resident; the readout tells those apart.
    public func appearanceSkipReasons(forActor formID: FormID) -> [String] {
        let prefix = "ACHR \(formID): "
        let summaries = streamer.interiorScene.map { [$0.summary] } ?? streamer.composition
            .actorSummaries()
        return summaries
            .flatMap(\.actorAppearanceSkipReasons)
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    /// Which resident cell holds a reference, so a Papyrus world write can be
    /// attributed to one cell instead of every resident one.
    public func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        if let interiorScene = streamer.interiorScene {
            return interiorScene.references[key] == nil ? nil : interiorScene.location
        }
        return streamer.composition.cellLocation(of: key)
    }

    public func activateInteractionTarget() {
        guard let interactionTarget = streamer.interactionTarget else { return }
        activate(interactionTarget)
    }

    /// One activation of `target`: the gate first, then the perk choices, the event,
    /// talk, and door. The lockpicking menu calls this again after a lock opens, and
    /// the perk choice menu with `offeringPerkChoices` false.
    public func activate(_ target: InteractionTarget, offeringPerkChoices: Bool = true) {
        if let refusal = streamer.activationGate.refusal(for: target) {
            streamer.activationGate.refusals(ActivationRefusalEvent(
                target: target,
                refusal: refusal
            ))
            return
        }
        if offeringPerkChoices, streamer.activationGate.perkChoices?(target) == true {
            return
        }
        streamer.events.onInteraction(InteractionEvent(target: target))
        // After the plain event, so an activated actor reaches the audio and
        // Papyrus subscribers in the same order an activated door does before
        // anything opens a menu on top of the world.
        if
            let event = TalkActivationEvent(
                interaction: target.interaction,
                pickedSpeaker: streamer.talk.speaker,
                placedKey: { referenceEntry(formID: target.interaction.reference)?.key }
            )
        {
            streamer.talk.activations(event)
        }
        guard
            target.interaction.action == .open,
            streamer.transitions
                .requestDoorTransition(activeDoor(reference: target.interaction.reference))
        else { return }
        streamer.doorState.doorTransitionHold = max(0, streamer.doorState.doors.teleportDelay)
        streamer.doorState.doorMotionInteraction = target.interaction
        streamer.events.onLoadDoorUsed?(target.interaction.reference)
        streamer.events.onInteractionAnimation?(InteractionAnimationEvent(
            interaction: target.interaction,
            phase: .motionStarted
        ))
    }

    private func activeDoor(reference: FormID) -> PlacedDoor? {
        if let interiorScene = streamer.interiorScene {
            return interiorScene.doors.first { $0.reference == reference }
        }
        return streamer.composition.door(reference: reference)
    }
}

/// The streamer is the app's answer to "what does this reference decode to,
/// and where is it right now" for the Papyrus world bridge. The
/// three members it needs already existed; the conformance only names them.
extension CellStreamer: PapyrusWorldReferenceSource {}
