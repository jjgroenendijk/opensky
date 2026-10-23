// What each MGEF archetype does, as one rule per archetype. Pure. The table and
// every quote come from the Creation Kit wiki's Magic Effect page
// (<https://ck.uesp.net/wiki/Magic_Effect>). See docs/engine/magic-archetypes.md.

import Foundation
import OpenSkyFormatsESM

/// Which effects a dispelling archetype removes.
nonisolated public enum MagicDispelFilter: Equatable, Sendable {
    /// Dispel: "Removes magic effects with a duration from the target."
    case timed
    /// Cure Disease: "Removes all disease effects from the target."
    case disease
    /// Cure Poison: "Removes all poison effects from the target."
    case poison
    /// Cure Paralysis: "Removes Paralysis on the target."
    case paralysis
}

/// A behaviour the combat loop reads through `ActorMagicInfluence`.
nonisolated public enum MagicInfluenceKind: Equatable, Sendable {
    case calm
    case frenzy
    case demoralize
    case rally
    case turnUndead
    case paralysis
    case etherealize
}

/// An archetype the session carries out, because it changes the world rather than
/// an actor value.
nonisolated public enum MagicWorldArchetype: Equatable, Sendable {
    /// "Staggers the target."
    case stagger
    /// "Creates the specified Hazard object at the target."
    case spawnHazard
    /// "Casts an effect spell on all targets in the area."
    case cloak
    /// "Creates the specified Weapon, and dispels it when the duration expires."
    case boundWeapon
    /// "Disarms targets up to level <MAG>."
    case disarm
    /// "If the target dies while this effect is active, fills a soul gem carried by
    /// the caster."
    case soulTrap
    /// "Slows time for all but the player by the indicated amount (a multiplier, with 1
    /// being normal time)."
    case slowTime
    /// "Summons the specified creature, placing them under the caster's control."
    case summon
    /// "If the target is dead, reanimate them, putting them under the caster's control."
    case reanimate
    /// "Banishes Summoned Actors up to level <MAG>."
    case banish
    /// "Takes control of Summoned Actors up to level <MAG>."
    case commandSummoned
    /// "Applies a visual effect to all valid targets in range."
    case detectLife
    /// "Creates the specified light object."
    case light
    /// "Any equipped (melee) weapon receives the specified enchantment until unequipped
    /// or until the effect wears off."
    case enhanceWeapon
    /// Werewolf and Vampire Lord: "Changes the target's race to the specified race."
    case changeRace
    /// "When cast on a dead actor, sets the HasBeenEaten property on actor from 0 to 1."
    case werewolfFeed
    /// "Applies the Telekinesis effect to the target object, allowing the caster to
    /// manipulate it at a distance."
    case telekinesis
    /// "Can pick up and throw selected NPC."
    case grabActor
    /// "Creates a trail of Hazard objects from the caster to the nearest quest target."
    case guide
}

nonisolated public enum MagicArchetypeRule: Equatable, Sendable {
    /// Value Modifier, Dual Value Modifier, Peak Value Modifier.
    case actorValues
    /// An actor value held at 1 while the effect runs.
    case heldFlag(actorValue: Int32)
    /// "Does up to <MAG> damage to the target's attribute, and restores the
    /// caster's attribute by the amount of damage done."
    case absorb
    /// "Grants up to <MAG> of a chosen actor value, but starts at 0 and increases
    /// over time."
    case accumulate
    case influence(MagicInfluenceKind)
    case dispel(MagicDispelFilter)
    /// "Has no effect other than any Papyrus Scripts specified", "Not Used", or an
    /// archetype that cannot reach its target. See docs/engine/magic-archetypes.md.
    case carrier
    /// "Modifies the target actor value by the computed magnitude times the
    /// fMagicVACPartTargetedMult Game Setting".
    case valueAndParts
    case world(MagicWorldArchetype)

    /// `Paralysis` in the vanilla actor-value table: "This will also set the
    /// boolean actor value Paralyze to 1 to prevent movement."
    public static let paralysisActorValue: Int32 = 53
    /// `Invisibility` in the vanilla actor-value table. Detection reads it.
    public static let invisibilityActorValue: Int32 = 54
    /// `Telekinesis`: "set the boolean actor value Telekinesis to 1 in order to allow you
    /// to see item stats at a distance."
    public static let telekinesisActorValue: Int32 = 88
    /// `Grabbed`, held at 1 on an actor Grab Actor holds.
    public static let grabbedActorValue: Int32 = 161
    /// `PerceptionCondition` through `BrainCondition`, the seven slots between
    /// `ResistDisease` (45) and `Paralysis` (53). Value and Parts changes each one.
    public static let bodyPartConditionValues: [Int32] = Array(46 ... 52)

    /// The rule for `archetype`, or nil while it has none.
    public static func rule(for archetype: MagicEffectArchetype) -> Self? {
        switch archetype {
        case .valueModifier, .dualValueModifier, .peakValueModifier: .actorValues
        case .absorb: .absorb
        case .accumulateMagnitude: .accumulate
        case .invisibility: .heldFlag(actorValue: invisibilityActorValue)
        case .script, .concussion, .cureAddiction, .lock, .open, .disguise,
             .spawnScriptedReference:
            .carrier
        case .valueAndParts: .valueAndParts
        case .dispel: .dispel(.timed)
        case .cureDisease: .dispel(.disease)
        case .curePoison: .dispel(.poison)
        case .cureParalysis: .dispel(.paralysis)
        default: worldRule(for: archetype) ?? influenceRule(for: archetype)
        }
    }

    private static func worldRule(for archetype: MagicEffectArchetype) -> Self? {
        worldArchetypes[archetype].map { .world($0) }
    }

    private static let worldArchetypes: [MagicEffectArchetype: MagicWorldArchetype] = [
        .stagger: .stagger, .spawnHazard: .spawnHazard, .cloak: .cloak,
        .boundWeapon: .boundWeapon, .disarm: .disarm, .soulTrap: .soulTrap,
        .slowTime: .slowTime, .summonCreature: .summon, .reanimate: .reanimate,
        .banish: .banish, .commandSummoned: .commandSummoned, .detectLife: .detectLife,
        .light: .light, .enhanceWeapon: .enhanceWeapon, .werewolf: .changeRace,
        .vampireLord: .changeRace, .werewolfFeed: .werewolfFeed,
        .telekinesis: .telekinesis, .grabActor: .grabActor, .guide: .guide
    ]

    private static func influenceRule(for archetype: MagicEffectArchetype) -> Self? {
        switch archetype {
        case .calm: .influence(.calm)
        case .frenzy: .influence(.frenzy)
        case .demoralize: .influence(.demoralize)
        case .rally: .influence(.rally)
        case .turnUndead: .influence(.turnUndead)
        case .paralysis: .influence(.paralysis)
        case .etherealize: .influence(.etherealize)
        default: nil
        }
    }

    /// Whether the magnitude is the highest target level the effect works on:
    /// "up to level <MAG>". Turn Undead is "similar to Demoralize".
    public var capsTargetLevel: Bool {
        switch self {
        case .influence(.calm), .influence(.frenzy), .influence(.demoralize),
             .influence(.rally), .influence(.turnUndead), .world(.disarm),
             .world(.reanimate), .world(.banish), .world(.commandSummoned):
            true
        default:
            false
        }
    }

    /// Whether the effect does anything once, at the moment it lands, rather than
    /// for as long as it runs.
    public var actsOnce: Bool {
        switch self {
        case .dispel, .world(.stagger), .world(.spawnHazard), .world(.disarm),
             .world(.banish), .world(.commandSummoned), .world(.werewolfFeed),
             .world(.changeRace), .world(.detectLife), .world(.telekinesis),
             .world(.grabActor), .world(.guide):
            true
        default: false
        }
    }

    /// Whether the effect only works while it runs, so a zero duration does
    /// nothing. A constant effect still runs.
    public var needsDuration: Bool {
        switch self {
        case .influence, .heldFlag, .accumulate, .world(.cloak), .world(.boundWeapon),
             .world(.soulTrap), .world(.slowTime), .world(.summon), .world(.reanimate),
             .world(.light), .world(.enhanceWeapon):
            true
        default: false
        }
    }
}
