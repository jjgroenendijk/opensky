// The actor half of the native-to-world seam (issue #375, roadmap item 15.8):
// what an `Actor` native is allowed to ask of the session, and the nonisolated
// hops the native bodies actually call.
//
// A protocol of its own that `PapyrusWorldBridge` refines, exactly as the quest
// half is, and for the same reason: actors are a subsystem with their own
// vocabulary — values, maximums, death, hostility — and a test that only cares
// about actors should be able to read this list on its own.
//
// ## Why reads come back as one observation
//
// `actorState(for:)` answers with a whole `PapyrusActorState` rather than with
// one getter per question. Five natives read this actor and three of them are
// the same number at different scalings; taking one observation is what stops
// `GetActorValue` and `GetActorValuePercentage` from straddling a mutation and
// disagreeing about the same actor in the same script line.
//
// ## Why the mutations answer with the state afterwards
//
// `DamageActorValue` has to know whether the blow it just landed emptied the
// bar, because that is what turns a damage into a death. Returning the stored
// state means the native never re-reads and never races its own write. The
// death itself is not the native's to declare: the bridge routes it, so a
// script kill and a sword kill reach `RagdollRuntime.noteZeroHealth` by one
// path and the death events fire exactly once from the death latch.
//
// Documented in docs/engine/papyrus-vm.md.

import Foundation

/// Which of the three base-and-modifier writes a script asked for (issue #496,
/// roadmap item 20.3).
///
/// One enumeration and one bridge method rather than three of each, because the
/// three differ only in which slot they land in and every other step — find the
/// actor, reject an unknown value name, route a health that reached zero into
/// the death path — is shared. The semantics of each case are quoted at
/// `ActorValueRuntime.setBase(at:to:on:)`, `addModifier(_:to:at:on:)` and
/// `forceValue(at:to:on:)`.
nonisolated enum PapyrusActorValueWrite: String, CaseIterable, Equatable, Sendable {
    /// `SetActorValue`: sets the base value, leaving every modifier intact.
    case setBase = "SetActorValue"
    /// `ModActorValue`: adds to the permanent modifier, which moves the
    /// maximum and the current value together.
    case modify = "ModActorValue"
    /// `ForceActorValue`: moves the permanent modifier so the current value
    /// lands exactly on the number asked for.
    case force = "ForceActorValue"
}

/// One actor as a Papyrus native sees it.
nonisolated struct PapyrusActorState: ActorValueReadable, Equatable, Sendable {
    /// Current health, magicka and stamina.
    let current: ActorValues
    /// Re-derived maximums, which is what `GetBaseActorValue` reports.
    let maximums: ActorValues
    /// Whether `ActorDeathState` has latched.
    let isDead: Bool
    /// Whether the actor is actually in a fight, per 16.7's behavior phase.
    /// Searching counts; being hostile without having noticed anybody does not.
    let isInCombat: Bool
    /// The same answer at `GetCombatState`'s three-value resolution.
    let combatActivity: ActorCombatActivity
    /// Where the actor's weapon is, or nil when nothing in this session
    /// observes a draw state for it. Only the player carries a behavior graph
    /// that tracks one today, so every other actor answers nil and
    /// `IsWeaponDrawn` fails with a reason rather than claiming sheathed.
    let weaponDrawState: WeaponDrawState?
    /// Non-primary actor values this actor has moved off its baseline
    /// (issue #468), which is what lets `GetActorValue("Resist Fire")` answer
    /// rather than fail with "no store for actor value".
    let general: [Int32: ActorValueEntry]
    /// Non-primary base values this actor's records author, which is what
    /// `GetBaseActorValue` reports for them.
    let generalBaseline: [Int32: Float]
    /// Whether this actor is the player, which is what the resistance cap
    /// depends on.
    let isPlayer: Bool

    init(
        current: ActorValues,
        maximums: ActorValues,
        isDead: Bool = false,
        isInCombat: Bool = false,
        combatActivity: ActorCombatActivity = .notFighting,
        weaponDrawState: WeaponDrawState? = nil,
        general: [Int32: ActorValueEntry] = [:],
        generalBaseline: [Int32: Float] = [:],
        isPlayer: Bool = false
    ) {
        self.current = current
        self.maximums = maximums
        self.isDead = isDead
        self.isInCombat = isInCombat
        self.combatActivity = combatActivity
        self.weaponDrawState = weaponDrawState
        self.general = general
        self.generalBaseline = generalBaseline
        self.isPlayer = isPlayer
    }
}

/// Actor state and mutations a Papyrus native may perform.
///
/// `Sendable` for the reason `PapyrusWorldQuestBridge` is: every conformer is a
/// `@MainActor` class, and the existential only needed to say so before
/// `PapyrusWorldAccess` can carry it across its hops.
@MainActor
protocol PapyrusWorldActorBridge: AnyObject, Sendable {
    /// One observation of the actor `key` names, or nil when this session
    /// tracks no actor there — no actor-value runtime attached, or a key no
    /// resident cell resolves to a placed actor.
    func actorState(for key: ReferenceKey) -> PapyrusActorState?

    /// Takes `amount` off one of `key`'s values through `ActorValueRuntime`,
    /// then routes a health that reached zero into the death path.
    ///
    /// Addressed by vanilla actor-value index rather than by
    /// `ActorValueKind` since 19.5, because a script may damage any of the 164
    /// and only three of them have a kind.
    ///
    /// - Returns: the state as stored afterwards, or nil when there was no
    ///   actor to damage.
    @discardableResult
    func damageActorValue(
        at index: Int32, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState?

    /// Adds `amount` to one of `key`'s values, capped at its maximum.
    ///
    /// Never resurrects: restoring health on a latched corpse writes the health
    /// and leaves the corpse dead, because `Resurrect` is the function that
    /// clears a death and it is not implemented.
    ///
    /// - Returns: the state as stored afterwards, or nil when there was no
    ///   actor to restore.
    @discardableResult
    func restoreActorValue(
        at index: Int32, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState?

    /// Sets, modifies or forces one of `key`'s actor values (issue #496).
    ///
    /// A health that reaches zero becomes a death on the same call, exactly as
    /// it does through `damageActorValue`: a script that forces health to zero
    /// and then asks `IsDead()` must not read a live actor lying on the floor.
    ///
    /// - Returns: the state as stored afterwards, or nil when there was no
    ///   actor to write to and when the index names no actor value.
    @discardableResult
    func writeActorValue(
        _ write: PapyrusActorValueWrite,
        at index: Int32,
        to value: Float,
        on key: ReferenceKey
    ) -> PapyrusActorState?

    /// Starts `key` fighting `target` at once, without waiting for it to
    /// perceive anything (issue #424). Writes hostility through the world-state
    /// store on the way, so a scripted fight is saved exactly as one the player
    /// started.
    ///
    /// - Returns: true when the actor is now fighting. False for an actor this
    ///   session does not track and for a target other than the player, which
    ///   is a fight nothing in this engine simulates.
    @discardableResult
    func startActorCombat(_ key: ReferenceKey, target: ReferenceKey) -> Bool

    /// Ends `key`'s fight and hands it back to its package, leaving its stored
    /// hostility alone.
    ///
    /// - Returns: true when there was a fight to stop.
    @discardableResult
    func stopActorCombat(_ key: ReferenceKey) -> Bool

    /// Kills `key` outright, attributing it to `killer` when the script named
    /// one. Health is emptied first, so a corpse never reads as dead at full
    /// health and the death takes the same route a fatal blow does.
    ///
    /// - Returns: true when this call is what killed the actor. An actor
    ///   already dead answers false and raises nothing, which is what makes
    ///   `OnDeath` fire exactly once.
    @discardableResult
    func killActor(_ key: ReferenceKey, killer: ReferenceKey?) -> Bool
}

/// Nonisolated hops for the actor operations, mirroring the rest of
/// `PapyrusWorldAccess`: one `MainActor.assumeIsolated` per method, which is an
/// assertion that natives run on the main actor rather than a suppression of
/// the check.
nonisolated extension PapyrusWorldAccess {
    func actorState(for key: ReferenceKey) -> PapyrusActorState? {
        MainActor.assumeIsolated { bridge.actorState(for: key) }
    }

    @discardableResult
    func damageActorValue(
        at index: Int32, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState? {
        MainActor.assumeIsolated {
            bridge.damageActorValue(at: index, by: amount, on: key)
        }
    }

    @discardableResult
    func restoreActorValue(
        at index: Int32, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState? {
        MainActor.assumeIsolated {
            bridge.restoreActorValue(at: index, by: amount, on: key)
        }
    }

    @discardableResult
    func writeActorValue(
        _ write: PapyrusActorValueWrite,
        at index: Int32,
        to value: Float,
        on key: ReferenceKey
    ) -> PapyrusActorState? {
        MainActor.assumeIsolated {
            bridge.writeActorValue(write, at: index, to: value, on: key)
        }
    }

    @discardableResult
    func startActorCombat(_ key: ReferenceKey, target: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { bridge.startActorCombat(key, target: target) }
    }

    @discardableResult
    func stopActorCombat(_ key: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { bridge.stopActorCombat(key) }
    }

    @discardableResult
    func killActor(_ key: ReferenceKey, killer: ReferenceKey?) -> Bool {
        MainActor.assumeIsolated { bridge.killActor(key, killer: killer) }
    }
}
