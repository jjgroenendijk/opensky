// `RagdollControlProviding` conformance (issue #197, roadmap item 15.6, scope
// point 7): the live readouts and controls the
// `World > Player & Locomotion > Death & Ragdoll` section is written against.
//
// Every field is a plain read off `RagdollWorld.statsSnapshot`, with no
// accounting invented at the UI. The trigger goes through the same
// `RagdollRuntime.trigger(_:)` a zero-health death reaches, so a collapse
// requested from the sidebar is indistinguishable downstream from one a fight
// caused — which is the whole point of offering it, because it makes the
// sidebar a way to verify the route rather than a second implementation of it.

import Foundation
import simd

extension GameViewController: RagdollControlProviding {
    var ragdollStatsSnapshot: RagdollStatsSnapshot {
        ragdoll.runtime?.world.statsSnapshot ?? RagdollStatsSnapshot()
    }

    /// Kills and ragdolls whichever actor the crosshair is on, falling back to
    /// the nearest resident one.
    ///
    /// The crosshair first because that is what "selected" means to someone
    /// looking at the screen; the nearest actor as a fallback because the
    /// player has no rendered body this milestone and an actor is easy to stand
    /// beside and hard to put a crosshair on.
    @discardableResult
    func triggerRagdoll() -> Bool {
        guard let runtime = ragdoll.runtime else {
            ragdoll.lastActionText = "Ragdoll unavailable: no renderer."
            return false
        }
        guard let key = selectedActorKey() else {
            ragdoll.lastActionText = "No actor selected: none is resident."
            return false
        }
        guard runtime.trigger(key) else {
            ragdoll.lastActionText =
                "\(key.description) has no ragdoll: its skeleton carries no bodies."
            return false
        }
        ragdoll.lastActionText = "Ragdolled \(key.description)."
        return true
    }

    func setRagdollFrozen(_ frozen: Bool) {
        ragdoll.runtime?.isFrozen = frozen
        ragdoll.lastActionText = frozen
            ? "Froze ragdoll stepping." : "Resumed ragdoll stepping."
    }

    func clearRagdolls() {
        ragdoll.runtime?.reset()
        renderer?.scene.ragdollPoses.removeAll()
        ragdoll.lastActionText = "Cleared every live ragdoll; the deaths stand."
    }

    /// Points the container menu at the nearest dead actor, so activating a
    /// corpse searches it (issue #197 scope point 6).
    ///
    /// No new menu and no new session type: `ContainerSession` opens over any
    /// `InventoryHolder`, and an ACHR's holder re-derives its baseline from the
    /// NPC_'s own CNTO list exactly as a chest's does. All this does is nominate
    /// one, which is the same call the crosshair makes for a chest.
    ///
    /// Nearest rather than the crosshair target, because ACHRs carry no
    /// `PlacedInteraction` — the cell build makes those from CONT, DOOR, ACTI,
    /// TREE, FURN and item bases, and an actor is none of them. Giving corpses a
    /// crosshair prompt of their own belongs with the rest of actor interaction
    /// in item 15.7, and inventing one here would put a "Search" prompt on the
    /// living too.
    ///
    /// - Returns: true when a corpse was nominated.
    @discardableResult
    func nominateNearestCorpse() -> Bool {
        guard
            let runtime = ragdoll.runtime,
            let streamer,
            let renderer,
            worldItems.runtime != nil
        else { return false }
        let feet = renderer.walkController.feetPosition
        let corpses = streamer.residentActorEntries()
            .filter { runtime.opensAsCorpse($0.key) }
        guard
            let entry = corpses.min(by: { first, second in
                Self.distance(first, to: feet) < Self.distance(second, to: feet)
            }),
            let actor = entry.placedActor
        else { return false }
        containerMenu.container = InventoryHolder(
            key: entry.key,
            owner: .actor(base: actor.base),
            cell: streamer.cellLocation(of: entry.key)
        )
        containerMenu.containerName = "Corpse \(entry.key.description)"
        containerMenu.containerReference = actor.formID
        runtime.noteLooted(entry.key)
        return true
    }

    // MARK: - Private

    private static func distance(_ entry: RuntimeReferenceEntry, to point: SIMD3<Float>) -> Float {
        guard let actor = entry.placedActor else { return .greatestFiniteMagnitude }
        return simd_length_squared(actor.placement.position - point)
    }

    /// The actor the trigger acts on: the crosshair target when it is an ACHR,
    /// else the resident actor nearest the player.
    private func selectedActorKey() -> ReferenceKey? {
        guard let streamer else { return nil }
        if
            let target = streamer.interactionTarget,
            let entry = streamer.referenceEntry(formID: target.interaction.reference),
            entry.placedActor != nil
        {
            return entry.key
        }
        guard let renderer else { return nil }
        return streamer.nearestActorEntry(to: renderer.walkController.feetPosition)?.key
    }
}
