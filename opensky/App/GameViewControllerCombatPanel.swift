// `CombatLoopControlProviding` conformance (issue #374, roadmap item 15.7,
// scope point 7): the live readouts and dev controls a Combat & Physics panel
// is written against.
//
// The protocol and this conformance ship now; the panel itself ships with the
// M15 acceptance gate (item 15.9), which is what the issue asks for. Writing
// the conformance now is what proves the runtime can answer the questions a
// panel asks — every field below is a plain read off `CombatLoopRuntime`, with
// no accounting invented at the UI.
//
// The hostility toggle acts on the *selected* actor, which is the nearest
// resident one. That is the same selector the actor-value controls use
// (`ActorValueTargetSelector.nearestActor`), deliberately: a developer aiming
// at an actor to damage it and aiming at it to anger it should not have to
// think about two different notions of "this one".

import Foundation

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
            devTargetName: combatActorName(runtime.devTarget),
            devTargetPhase: runtime.driver.phase,
            devTargetIsRunning: runtime.devTarget != nil,
            devTargetAttackCount: runtime.driver.attackCount,
            devTargetContactCount: runtime.driver.contactCount,
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

    @discardableResult
    func spawnCombatDevTarget() -> String {
        combat.runtime?.spawnDevTarget()
            ?? "Combat unavailable: no game data loaded."
    }

    @discardableResult
    func resetCombatDevTarget() -> String {
        combat.runtime?.resetDevTarget()
            ?? "Combat unavailable: no game data loaded."
    }

    func clearCombatTrace() {
        combat.runtime?.clearTrace()
    }

    // MARK: - Private

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
