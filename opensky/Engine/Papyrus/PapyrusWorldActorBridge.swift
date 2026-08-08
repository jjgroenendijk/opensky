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

/// One actor as a Papyrus native sees it.
nonisolated struct PapyrusActorState: Equatable, Sendable {
    /// Current health, magicka and stamina.
    let current: ActorValues
    /// Re-derived maximums, which is what `GetBaseActorValue` reports.
    let maximums: ActorValues
    /// Whether `ActorDeathState` has latched.
    let isDead: Bool
    /// Whether the actor is fighting the player, per 15.7's hostility.
    let isInCombat: Bool
    /// Where the actor's weapon is, or nil when nothing in this session
    /// observes a draw state for it. Only the player carries a behavior graph
    /// that tracks one today, so every other actor answers nil and
    /// `IsWeaponDrawn` fails with a reason rather than claiming sheathed.
    let weaponDrawState: WeaponDrawState?

    init(
        current: ActorValues,
        maximums: ActorValues,
        isDead: Bool = false,
        isInCombat: Bool = false,
        weaponDrawState: WeaponDrawState? = nil
    ) {
        self.current = current
        self.maximums = maximums
        self.isDead = isDead
        self.isInCombat = isInCombat
        self.weaponDrawState = weaponDrawState
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
    /// - Returns: the state as stored afterwards, or nil when there was no
    ///   actor to damage.
    @discardableResult
    func damageActorValue(
        _ kind: ActorValueKind, by amount: Float, on key: ReferenceKey
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
        _ kind: ActorValueKind, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState?

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
        _ kind: ActorValueKind, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState? {
        MainActor.assumeIsolated {
            bridge.damageActorValue(kind, by: amount, on: key)
        }
    }

    @discardableResult
    func restoreActorValue(
        _ kind: ActorValueKind, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState? {
        MainActor.assumeIsolated {
            bridge.restoreActorValue(kind, by: amount, on: key)
        }
    }

    @discardableResult
    func killActor(_ key: ReferenceKey, killer: ReferenceKey?) -> Bool {
        MainActor.assumeIsolated { bridge.killActor(key, killer: killer) }
    }
}
