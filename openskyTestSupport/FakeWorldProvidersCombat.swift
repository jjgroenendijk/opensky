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
}

extension FakeWorldProviders {
    var actorValueControlSnapshot: ActorValueControlSnapshot {
        actorValues.snapshot
    }

    var actorValueTarget: ActorValueTargetSelector {
        get { actorValues.target }
        set { actorValues.target = newValue }
    }

    @discardableResult
    func damageSelectedActor(_ kind: ActorValueKind, by amount: Float) -> String {
        actorValues.damages.append((kind: kind, amount: amount))
        return "Damaged \(kind.rawValue) by \(amount)."
    }

    @discardableResult
    func restoreSelectedActor(_ kind: ActorValueKind, by amount: Float) -> String {
        actorValues.restores.append((kind: kind, amount: amount))
        return "Restored \(kind.rawValue) by \(amount)."
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
    var spawnRequests = 0
    var resetRequests = 0
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

    @discardableResult
    func spawnCombatDevTarget() -> String {
        combatLoop.spawnRequests += 1
        return "Spawned dev target #\(combatLoop.spawnRequests)."
    }

    @discardableResult
    func resetCombatDevTarget() -> String {
        combatLoop.resetRequests += 1
        return "Reset the dev target."
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
