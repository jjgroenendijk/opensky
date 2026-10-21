// The actor, magic, progression, and crime families of the Papyrus world bridge.
// Each member stays optional: a nil member is a session without that runtime, and
// its natives refuse, which differs from a wired member that answers nil.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

/// The `Actor` native collaborators. See `PapyrusWorldStateBridgeActors.swift`.
public struct PapyrusActorNatives {
    public var actorValueRuntime: (() -> (any ActorValueAccess)?)?
    public var ragdollRuntime: (() -> (any DeathReporting)?)?
    /// The combat loop behind `StartCombat`, `StopCombat` and `IsInCombat`.
    public var combatRuntime: (() -> (any CombatControlling)?)?
    /// Where one actor's weapon is, or nil when this session observes no draw state for it.
    public var weaponDrawState: ((ReferenceKey) -> WeaponDrawState?)?

    public init() {}
}

/// The spell natives' collaborators.
public struct PapyrusMagicNatives {
    /// The spellbook and cast loop.
    public var casterRuntime: (() -> (any SpellCasting)?)?
    /// One dispel over the session's `ActiveEffectRuntime` value, with the write-back;
    /// answers how many effects went.
    public var dispelEffects: ((ActorValueHolder, @escaping (ActiveEffect) -> Bool) -> Int)?
    /// The seam projectiles and enchantments share, so `Spell.Cast` at a named target
    /// resists exactly as a fireball does.
    public var applySpellHit: ((SpellHit) -> SpellHitReport)?
    /// `Actor.TrapSoul`: the victim, then the caster; answers whether a gem filled.
    public var trapSoul: ((ReferenceKey, ReferenceKey) -> Bool)?

    public init() {}
}

/// Perks, skills, and perk points, each over a value the controller owns.
public struct PapyrusProgressionNatives {
    /// One perk grant or removal, with the ability reconcile; answers whether the set changed.
    public var mutatePerks: ((PapyrusPerkMutation, ReferenceKey, ReferenceKey) -> Bool)?
    /// The perks one actor owns, or nil when this session runs no perk runtime.
    public var perkOwnership: ((ReferenceKey) -> Set<ReferenceKey>?)?
    /// One scripted skill advance; answers whether the skill took it.
    public var advanceSkill: ((PapyrusSkillAdvance, Int32, Float) -> Bool)?
    /// Applies a delta to the player's perk points and returns the pool; zero reads it.
    public var modifyPerkPoints: ((Int) -> Int?)?

    public init() {}
}

/// Crime, arrest, and barter.
public struct PapyrusCrimeNatives {
    public var crimeReporter: (() -> (any CrimeReporting)?)?
    /// Arrest outcomes for `CanPayCrimeGold`, `PlayerPayCrimeGold` and `SendPlayerToJail`.
    /// The session owns them, because a sentence moves the clock and the player.
    public var arrestSession: (() -> (any CrimeArrestSession)?)?
    /// Opens the barter menu for `Actor.ShowBarterMenu`, with the readout line.
    public var showBarterMenu: ((ReferenceKey) -> (opened: Bool, text: String)?)?

    public init() {}
}
