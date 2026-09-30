// The actor half of the native-to-world seam: what an `Actor` native may ask of
// the session, and the nonisolated hops the natives call. `actorState(for:)`
// returns one observation, so related reads cannot straddle a write. Mutations
// return the state afterwards; the bridge routes deaths through
// `RagdollRuntime.noteZeroHealth`. See docs/engine/papyrus-actor-natives.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

/// Which of the three base-and-modifier writes a script asked for. One enum and
/// one bridge method, because only the slot differs. Semantics are at
/// `ActorValueRuntime.setBase(at:to:on:)`, `addModifier(_:to:at:on:)`, and
/// `forceValue(at:to:on:)`.
nonisolated public enum PapyrusActorValueWrite: String, CaseIterable, Equatable, Sendable {
    /// `SetActorValue`: sets the base value, leaving every modifier intact.
    case setBase = "SetActorValue"
    /// `ModActorValue`: adds to the permanent modifier, which moves the
    /// maximum and the current value together.
    case modify = "ModActorValue"
    /// `ForceActorValue`: moves the permanent modifier so the current value
    /// lands exactly on the number asked for.
    case force = "ForceActorValue"
}

/// Which way a scripted perk write goes. One enum, because only the direction
/// differs.
nonisolated public enum PapyrusPerkMutation: String, CaseIterable, Equatable, Sendable {
    case add = "AddPerk"
    case remove = "RemovePerk"
}

/// Which of the two scripted skill advances a native asked for. One enum,
/// because only the unit differs. Semantics are at
/// `SkillAdvancementRuntime.advance(skill:byUse:on:)` and `increment(skill:on:)`.
nonisolated public enum PapyrusSkillAdvance: String, CaseIterable, Equatable, Sendable {
    /// `Game.AdvanceSkill`: the magnitude is a skill *use* amount.
    case advance = "AdvanceSkill"
    /// `Game.IncrementSkill`: one whole skill point, and the magnitude is
    /// ignored.
    case increment = "IncrementSkill"
}

/// One actor as a Papyrus native sees it.
nonisolated public struct PapyrusActorState: ActorValueReadable, Equatable, Sendable {
    /// Current health, magicka and stamina.
    public let current: ActorValues
    /// Re-derived maximums, which is what `GetBaseActorValue` reports.
    public let maximums: ActorValues
    /// Whether `ActorDeathState` has latched.
    public let isDead: Bool
    /// Whether the actor is actually in a fight, per 16.7's behavior phase.
    /// Searching counts; being hostile without having noticed anybody does not.
    public let isInCombat: Bool
    /// Where the actor's weapon is, or nil when nothing in this session
    /// observes a draw state for it. Only the player carries a behavior graph
    /// that tracks one today, so every other actor answers nil and
    /// `IsWeaponDrawn` fails with a reason rather than claiming sheathed.
    public let weaponDrawState: WeaponDrawState?
    /// Non-primary actor values this actor has moved off its baseline, so
    /// `GetActorValue("Resist Fire")` answers.
    public let general: [Int32: ActorValueEntry]
    /// Non-primary base values this actor's records author, which is what
    /// `GetBaseActorValue` reports for them.
    public let generalBaseline: [Int32: Float]
    /// The actor's level, which `Actor.GetLevel` reports.
    public let level: Int

    public init(
        current: ActorValues,
        maximums: ActorValues,
        isDead: Bool = false,
        isInCombat: Bool = false,
        weaponDrawState: WeaponDrawState? = nil,
        general: [Int32: ActorValueEntry] = [:],
        generalBaseline: [Int32: Float] = [:],
        level: Int = PlayerLevelSource.startingLevel
    ) {
        self.current = current
        self.maximums = maximums
        self.isDead = isDead
        self.isInCombat = isInCombat
        self.weaponDrawState = weaponDrawState
        self.general = general
        self.generalBaseline = generalBaseline
        self.level = max(PlayerLevelSource.startingLevel, level)
    }
}

/// Actor state and mutations a Papyrus native may perform.
///
/// `Sendable` for the reason `PapyrusWorldQuestBridge` is: every conformer is a
/// `@MainActor` class, and the existential only needed to say so before
/// `PapyrusWorldAccess` can carry it across its hops.
@MainActor
public protocol PapyrusWorldActorBridge: AnyObject, Sendable {
    /// One observation of the actor `key` names, or nil when this session
    /// tracks no actor there — no actor-value runtime attached, or a key no
    /// resident cell resolves to a placed actor.
    func actorState(for key: ReferenceKey) -> PapyrusActorState?

    /// Takes `amount` off one of `key`'s values through `ActorValueRuntime`, then
    /// routes zero health into the death path. Addressed by vanilla index.
    /// - Returns: the state as stored afterwards, or nil when there was no actor.
    @discardableResult
    func damageActorValue(
        at index: Int32, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState?

    /// Adds `amount` to one of `key`'s values, capped at its maximum. Never
    /// resurrects: `Resurrect` is not implemented.
    /// - Returns: the state as stored afterwards, or nil when there was no actor.
    @discardableResult
    func restoreActorValue(
        at index: Int32, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState?

    /// Sets, modifies, or forces one of `key`'s actor values. Zero health becomes a
    /// death in the same call.
    /// - Returns: the state as stored afterwards, or nil for no actor or an unknown
    ///   index.
    @discardableResult
    func writeActorValue(
        _ write: PapyrusActorValueWrite,
        at index: Int32,
        to value: Float,
        on key: ReferenceKey
    ) -> PapyrusActorState?

    /// Starts `key` fighting `target` at once, writing hostility through the store.
    /// - Returns: true when the actor is now fighting. False for an untracked actor
    ///   or a target other than the player.
    @discardableResult
    func startActorCombat(_ key: ReferenceKey, target: ReferenceKey) -> Bool

    /// Ends `key`'s fight and hands it back to its package, leaving its stored
    /// hostility alone.
    ///
    /// - Returns: true when there was a fight to stop.
    @discardableResult
    func stopActorCombat(_ key: ReferenceKey) -> Bool

    /// Gives `key` one perk through `PerkRuntime` and applies its abilities.
    /// - Returns: true when the perk was not already owned. False for an untracked
    ///   actor, no perk data, or a record this load order lacks.
    @discardableResult
    func addPerk(_ perk: ReferenceKey, to key: ReferenceKey) -> Bool

    /// Takes one perk away, revoking the abilities it granted.
    ///
    /// - Returns: true when the perk was owned.
    @discardableResult
    func removePerk(_ perk: ReferenceKey, from key: ReferenceKey) -> Bool

    /// Whether `key` owns `perk`, or nil when this session runs no perk
    /// runtime — a synthetic scene with no PERK index, where answering false
    /// would read as an actor who has taken nothing.
    func hasPerk(_ perk: ReferenceKey, on key: ReferenceKey) -> Bool?

    /// Advances one of the player's skills through `SkillAdvancementRuntime`.
    /// - Returns: false without a progression runtime, or for a skill with no
    ///   advancement parameters. Both are tallied failures.
    @discardableResult
    func advancePlayerSkill(
        _ advance: PapyrusSkillAdvance, at index: Int32, by magnitude: Float
    ) -> Bool

    /// The player's unspent perk points, or nil without character leveling, where
    /// zero would mislead.
    func playerPerkPoints() -> Int?

    /// Adds or removes perk points, clamped to the documented pool bounds.
    ///
    /// - Returns: the pool afterwards, or nil for a session with no character
    ///   leveling.
    @discardableResult
    func modifyPlayerPerkPoints(by delta: Int) -> Int?

    /// Kills `key`, attributing it to `killer` when named. Health is emptied first,
    /// so the death takes the fatal-blow route.
    /// - Returns: true when this call killed the actor; false for one already dead.
    @discardableResult
    func killActor(_ key: ReferenceKey, killer: ReferenceKey?) -> Bool
}

/// Nonisolated hops for the actor operations, mirroring the rest of
/// `PapyrusWorldAccess`: one `MainActor.assumeIsolated` per method, which is an
/// assertion that natives run on the main actor rather than a suppression of
/// the check.
nonisolated extension PapyrusWorldAccess {
    public func actorState(for key: ReferenceKey) -> PapyrusActorState? {
        MainActor.assumeIsolated { bridge.actorState(for: key) }
    }

    @discardableResult
    public func damageActorValue(
        at index: Int32, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState? {
        MainActor.assumeIsolated {
            bridge.damageActorValue(at: index, by: amount, on: key)
        }
    }

    @discardableResult
    public func restoreActorValue(
        at index: Int32, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState? {
        MainActor.assumeIsolated {
            bridge.restoreActorValue(at: index, by: amount, on: key)
        }
    }

    @discardableResult
    public func writeActorValue(
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
    public func startActorCombat(_ key: ReferenceKey, target: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { bridge.startActorCombat(key, target: target) }
    }

    @discardableResult
    public func stopActorCombat(_ key: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { bridge.stopActorCombat(key) }
    }

    @discardableResult
    public func killActor(_ key: ReferenceKey, killer: ReferenceKey?) -> Bool {
        MainActor.assumeIsolated { bridge.killActor(key, killer: killer) }
    }

    @discardableResult
    public func addPerk(_ perk: ReferenceKey, to key: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { bridge.addPerk(perk, to: key) }
    }

    @discardableResult
    public func removePerk(_ perk: ReferenceKey, from key: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { bridge.removePerk(perk, from: key) }
    }

    public func hasPerk(_ perk: ReferenceKey, on key: ReferenceKey) -> Bool? {
        MainActor.assumeIsolated { bridge.hasPerk(perk, on: key) }
    }

    @discardableResult
    public func advancePlayerSkill(
        _ advance: PapyrusSkillAdvance, at index: Int32, by magnitude: Float
    ) -> Bool {
        MainActor.assumeIsolated {
            bridge.advancePlayerSkill(advance, at: index, by: magnitude)
        }
    }

    public func playerPerkPoints() -> Int? {
        MainActor.assumeIsolated { bridge.playerPerkPoints() }
    }

    @discardableResult
    public func modifyPlayerPerkPoints(by delta: Int) -> Int? {
        MainActor.assumeIsolated { bridge.modifyPlayerPerkPoints(by: delta) }
    }
}
