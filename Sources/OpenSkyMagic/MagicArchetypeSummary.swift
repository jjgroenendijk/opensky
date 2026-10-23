// What each archetype rule does, in a few words for the Magic Effects panel.
// See docs/engine/magic-archetypes.md.

import Foundation

nonisolated extension MagicArchetypeRule {
    /// A few words on what the rule does to the actor or the world.
    public var summary: String {
        switch self {
        case .actorValues: "changes actor values"
        case .heldFlag: "holds a flag actor value at 1"
        case .absorb: "moves a value from target to caster"
        case .accumulate: "grows a value over one second"
        case let .influence(kind): kind.summary
        case let .dispel(filter): filter.summary
        case .carrier: "carries scripts only"
        case .valueAndParts: "changes an actor value, scaled"
        case let .world(archetype): archetype.summary
        }
    }
}

nonisolated extension MagicInfluenceKind {
    var summary: String {
        switch self {
        case .calm: "stops fighting"
        case .frenzy: "attacks the player"
        case .demoralize, .turnUndead: "flees"
        case .rally: "never flees"
        case .paralysis: "cannot move"
        case .etherealize: "deals and takes no damage"
        }
    }
}

nonisolated extension MagicDispelFilter {
    var summary: String {
        switch self {
        case .timed: "removes timed effects"
        case .disease: "cures diseases"
        case .poison: "cures poisons"
        case .paralysis: "cures paralysis"
        }
    }
}

nonisolated extension MagicWorldArchetype {
    var summary: String {
        switch self {
        case .stagger: "staggers"
        case .spawnHazard: "places a hazard"
        case .cloak: "casts its spell on nearby foes"
        case .boundWeapon: "conjures a weapon"
        case .disarm: "unequips weapons"
        case .soulTrap: "traps the soul on death"
        case .slowTime: "slows the world"
        case .summon: "summons a creature"
        case .reanimate: "raises the dead"
        case .banish: "sends a summon away"
        case .commandSummoned: "takes control of a summon"
        case .detectLife: "paints living actors nearby"
        case .light: "carries a light"
        case .enhanceWeapon: "enchants the melee weapon"
        case .changeRace: "changes race"
        case .werewolfFeed: "marks a corpse eaten"
        case .telekinesis: "holds a loose object"
        case .grabActor: "lifts an actor"
        case .guide: "lays a trail to the quest target"
        }
    }
}
