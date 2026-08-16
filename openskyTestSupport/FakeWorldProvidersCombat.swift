// The combat-and-physics half of the world-provider fake (issues #194, #374,
// #193), in its own file so `FakeWorldProviders` stays inside the type-length
// cap — the same split `FakeWorldProvidersLocomotion.swift` made.
//
// These three seams were specified and conformed one milestone item at a time
// and consumed all at once by the `World > Combat & Physics` panel the M15 gate
// ships (issue #198). Every answer is a plain stored value and every action is
// recorded rather than performed, which is what lets a panel test drive the
// whole destination with no renderer, no window and no game data.

@testable import opensky

/// The actor-value half of the fake's stored state (issue #194).
struct FakeActorValueState {
    var snapshot = ActorValueControlSnapshot.unavailable
    var target = ActorValueTargetSelector.player
    /// Every damage and restore the panel asked for, in order, so a gate can
    /// assert that a button sent exactly what the field held.
    var damages: [(kind: ActorValueKind, amount: Float)] = []
    var restores: [(kind: ActorValueKind, amount: Float)] = []
    var refillCount = 0
    var resetCount = 0
    /// Which actor value the controls last acted on, by vanilla table index
    /// (issue #468). Health until a panel selects another.
    var selection: Int32 = 24
    /// Every `Set` the panel asked for, newest last.
    var sets: [(index: Int32, value: Float)] = []
}

extension FakeWorldProviders {
    var actorValueControlSnapshot: ActorValueControlSnapshot {
        actorValues.snapshot
    }

    var actorValueTarget: ActorValueTargetSelector {
        get { actorValues.target }
        set { actorValues.target = newValue }
    }

    var actorValueSelection: Int32 {
        get { actorValues.selection }
        set { actorValues.selection = newValue }
    }

    /// The primary the current selection names, so the recorded damages and
    /// restores keep reading as they did before item 19.5 made the selection an
    /// index. A non-primary selection records as health, and the index the
    /// panel asked for is `actorValues.selection`.
    private var selectedKind: ActorValueKind {
        ActorValueIdentity.kind(at: actorValues.selection) ?? .health
    }

    @discardableResult
    func damageSelectedActor(by amount: Float) -> String {
        actorValues.damages.append((kind: selectedKind, amount: amount))
        return "Damaged \(ActorValueIdentity.description(of: actorValues.selection))"
            + " by \(amount)."
    }

    @discardableResult
    func restoreSelectedActor(by amount: Float) -> String {
        actorValues.restores.append((kind: selectedKind, amount: amount))
        return "Restored \(ActorValueIdentity.description(of: actorValues.selection))"
            + " by \(amount)."
    }

    @discardableResult
    func setSelectedActorValue(to value: Float) -> String {
        actorValues.sets.append((index: actorValues.selection, value: value))
        return "Set \(ActorValueIdentity.description(of: actorValues.selection))"
            + " to \(value)."
    }

    @discardableResult
    func restoreSelectedActorFully() -> String {
        actorValues.refillCount += 1
        return "Refilled every bar."
    }

    @discardableResult
    func resetSelectedActorValues() -> String {
        actorValues.resetCount += 1
        return "Reset to derived values."
    }
}

/// The combat-loop half of the fake's stored state (issue #374).
struct FakeCombatLoopState {
    var snapshot = CombatLoopSnapshot.unavailable
    var isHostile = false
    var traceClearCount = 0
}

extension FakeWorldProviders {
    var combatLoopSnapshot: CombatLoopSnapshot {
        combatLoop.snapshot
    }

    var selectedActorIsHostile: Bool {
        get { combatLoop.isHostile }
        set { combatLoop.isHostile = newValue }
    }

    func clearCombatTrace() {
        combatLoop.traceClearCount += 1
    }
}

/// The dynamic-body half of the fake's stored state (issue #193).
struct FakePhysicsState {
    var snapshot = DynamicBodyStatsSnapshot()
    var resetCount = 0
}

extension FakeWorldProviders {
    var dynamicBodyStatsSnapshot: DynamicBodyStatsSnapshot {
        physics.snapshot
    }

    func setPhysicsFrozen(_ frozen: Bool) {
        physics.snapshot.isFrozen = frozen
    }

    func resetDynamicBodies() {
        physics.resetCount += 1
    }
}
