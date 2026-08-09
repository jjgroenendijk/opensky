// `CombatLoopControlProviding` conformance (issues #374 and #424, roadmap items
// 15.7 and 16.7): the live readouts and the hostility control the Combat &
// Physics panel is written against.
//
// Every field below is a plain read off `CombatLoopRuntime`, with no accounting
// invented at the UI. Item 16.7 removed the dev-target spawn and reset actions
// along with the clock they drove, and added the per-actor readout that replaced
// them: one entry per actor with a behavior machine, nearest first, carrying the
// phase, the awareness, the distance, the health and the four counts.
//
// The hostility toggle acts on the *selected* actor, which is the nearest
// resident one. That is the same selector the actor-value controls use
// (`ActorValueTargetSelector.nearestActor`), deliberately: a developer aiming
// at an actor to damage it and aiming at it to anger it should not have to
// think about two different notions of "this one".

import Foundation
import simd

extension GameViewController: CombatLoopControlProviding {
    var combatLoopSnapshot: CombatLoopSnapshot {
        guard let runtime = combat.runtime else { return .unavailable }
        let selected = selectedCombatActor()
        return CombatLoopSnapshot(
            isAvailable: true,
            isPlayerInCombat: runtime.state.isPlayerInCombat,
            targetName: runtime.state.target == nil ? "—" : runtime.state.targetName,
            targetDistance: runtime.state.targetDistance,
            hostileCount: runtime.state.hostileCount,
            deadCount: runtime.state.deadCount,
            engagedCount: runtime.state.engagedCount,
            searchingCount: runtime.state.searchingCount,
            actors: combatActorReadouts(runtime: runtime),
            crowdedOutCount: runtime.crowdedOutCount,
            selectedActorName: combatActorName(selected),
            selectedActorIsHostile: selected.map { runtime.hostility(of: $0) == .hostile }
                ?? false,
            incomingHitCount: runtime.incomingHitCount,
            incomingTrace: runtime.incomingTrace.map(CombatLoopReadout.traceLine(for:)),
            damageFlash: runtime.playerDamageFlash,
            transients: combatTransients,
            limits: runtime.limits,
            trimmedTransients: runtime.trimmedTransients,
            lastActionText: runtime.lastActionText
        )
    }

    var selectedActorIsHostile: Bool {
        get {
            guard let runtime = combat.runtime, let key = selectedCombatActor() else {
                return false
            }
            return runtime.hostility(of: key) == .hostile
        }
        set {
            guard let runtime = combat.runtime else { return }
            guard let key = selectedCombatActor() else {
                runtime.record("Hostility: no resident actor to act on.")
                return
            }
            runtime.setHostility(newValue ? .hostile : .neutral, on: key)
            runtime.record(
                "Hostility: \(combatActorName(key)) is now"
                    + " \(newValue ? "hostile" : "neutral")."
            )
        }
    }

    func clearCombatTrace() {
        combat.runtime?.clearTrace()
    }

    // MARK: - Private

    /// One readout line per actor with a behavior machine, nearest first.
    ///
    /// Built from the same `combatActors()` observation the runtime stepped
    /// against, so the distance in the readout is the distance the fight used
    /// rather than one sampled a frame later.
    private func combatActorReadouts(runtime: CombatLoopRuntime) -> [CombatActorReadout] {
        let player = combatPlayer.feet
        return combatActors().compactMap { actor in
            guard let machine = runtime.behaviors[actor.key] else { return nil }
            return CombatActorReadout(
                key: actor.key,
                name: actor.name,
                phase: machine.phase,
                awareness: combatAwareness(of: actor.key, toward: .player).state,
                distance: simd_distance(actor.feet, player),
                healthFraction: combatHealthFraction(of: actor.key),
                attackCount: machine.attackCount,
                contactCount: machine.contactCount,
                blockCount: machine.blockCount,
                searchCount: machine.searchCount
            )
        }
        .sorted { ($0.distance, $0.key) < ($1.distance, $1.key) }
    }

    /// The actor the hostility toggle acts on: the nearest resident one.
    private func selectedCombatActor() -> ReferenceKey? {
        nearestActorValueHolder()?.key
    }

    /// A display name for one actor, matching the one `combatActors()` builds
    /// so the two readouts agree.
    private func combatActorName(_ key: ReferenceKey?) -> String {
        guard let key else { return "—" }
        return combatActors().first { $0.key == key }?.name ?? key.description
    }
}
