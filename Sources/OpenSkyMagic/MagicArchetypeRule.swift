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
    /// "Has no effect other than any Papyrus Scripts specified", or "Not Used".
    case carrier
    case world(MagicWorldArchetype)

    /// `Paralysis` in the vanilla actor-value table: "This will also set the
    /// boolean actor value Paralyze to 1 to prevent movement."
    public static let paralysisActorValue: Int32 = 53
    /// `Invisibility` in the vanilla actor-value table. Detection reads it.
    public static let invisibilityActorValue: Int32 = 54

    /// The rule for `archetype`, or nil while it has none.
    public static func rule(for archetype: MagicEffectArchetype) -> Self? {
        switch archetype {
        case .valueModifier, .dualValueModifier, .peakValueModifier: .actorValues
        case .absorb: .absorb
        case .accumulateMagnitude: .accumulate
        case .invisibility: .heldFlag(actorValue: invisibilityActorValue)
        case .script, .concussion, .cureAddiction: .carrier
        case .dispel: .dispel(.timed)
        case .cureDisease: .dispel(.disease)
        case .curePoison: .dispel(.poison)
        case .cureParalysis: .dispel(.paralysis)
        default: worldRule(for: archetype) ?? influenceRule(for: archetype)
        }
    }

    private static func worldRule(for archetype: MagicEffectArchetype) -> Self? {
        switch archetype {
        case .stagger: .world(.stagger)
        case .spawnHazard: .world(.spawnHazard)
        case .cloak: .world(.cloak)
        case .boundWeapon: .world(.boundWeapon)
        case .disarm: .world(.disarm)
        default: nil
        }
    }

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
             .influence(.rally), .influence(.turnUndead), .world(.disarm):
            true
        default:
            false
        }
    }

    /// Whether the effect does anything once, at the moment it lands, rather than
    /// for as long as it runs.
    public var actsOnce: Bool {
        switch self {
        case .dispel, .world(.stagger), .world(.spawnHazard), .world(.disarm): true
        default: false
        }
    }

    /// Whether the effect only works while it runs, so a zero duration does
    /// nothing. A constant effect still runs.
    public var needsDuration: Bool {
        switch self {
        case .influence, .heldFlag, .accumulate, .world(.cloak), .world(.boundWeapon): true
        default: false
        }
    }
}
