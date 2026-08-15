// MGEF DATA enum vocabulary from xEdit dev-4.1.6
// Core/wbDefinitionsTES5.pas `wbRecord(MGEF, ...)`. Unknown values remain
// explicit so mod-authored extensions survive decode.

import Foundation

nonisolated enum MagicEffectCastingType: Equatable, CustomStringConvertible {
    case constantEffect
    case fireAndForget
    case concentration
    /// SCRL only. `wbCastEnum` stops at 2; xEdit gives SCRL its own casting
    /// enum whose single member is 3, "Scroll" (`wbRecord(SCRL, ...)`), so the
    /// value is named here instead of surfacing as an unknown on every scroll.
    case scroll
    case unknown(raw: UInt32)

    init(rawValue: UInt32) {
        self = switch rawValue {
        case 0: .constantEffect
        case 1: .fireAndForget
        case 2: .concentration
        case 3: .scroll
        default: .unknown(raw: rawValue)
        }
    }

    var description: String {
        switch self {
        case .constantEffect: "constant effect"
        case .fireAndForget: "fire and forget"
        case .concentration: "concentration"
        case .scroll: "scroll"
        case let .unknown(raw): "unknown(\(raw))"
        }
    }
}

nonisolated enum MagicEffectDelivery: Equatable, CustomStringConvertible {
    case selfTarget
    case touch
    case aimed
    case targetActor
    case targetLocation
    case unknown(raw: UInt32)

    init(rawValue: UInt32) {
        self = switch rawValue {
        case 0: .selfTarget
        case 1: .touch
        case 2: .aimed
        case 3: .targetActor
        case 4: .targetLocation
        default: .unknown(raw: rawValue)
        }
    }

    var description: String {
        switch self {
        case .selfTarget: "self"
        case .touch: "touch"
        case .aimed: "aimed"
        case .targetActor: "target actor"
        case .targetLocation: "target location"
        case let .unknown(raw): "unknown(\(raw))"
        }
    }
}

nonisolated enum MagicEffectArchetype: Hashable, CustomStringConvertible {
    case valueModifier
    case script
    case dispel
    case cureDisease
    case absorb
    case dualValueModifier
    case calm
    case demoralize
    case frenzy
    case disarm
    case commandSummoned
    case invisibility
    case light
    case unknown13
    case unknown14
    case lock
    case open
    case boundWeapon
    case summonCreature
    case detectLife
    case telekinesis
    case paralysis
    case reanimate
    case soulTrap
    case turnUndead
    case guide
    case werewolfFeed
    case cureParalysis
    case cureAddiction
    case curePoison
    case concussion
    case valueAndParts
    case accumulateMagnitude
    case stagger
    case peakValueModifier
    case cloak
    case werewolf
    case slowTime
    case rally
    case enhanceWeapon
    case spawnHazard
    case etherealize
    case banish
    case spawnScriptedReference
    case disguise
    case grabActor
    case vampireLord
    case unknown(raw: UInt32)

    init(rawValue: UInt32) {
        self = Self.known[rawValue] ?? .unknown(raw: rawValue)
    }

    var description: String {
        guard case let .unknown(raw) = self else {
            return Self.names[Self.rawValues[self] ?? UInt32.max] ?? "unknown"
        }
        return "unknown(\(raw))"
    }

    private static let known: [UInt32: Self] = [
        0: .valueModifier, 1: .script, 2: .dispel, 3: .cureDisease, 4: .absorb,
        5: .dualValueModifier, 6: .calm, 7: .demoralize, 8: .frenzy, 9: .disarm,
        10: .commandSummoned, 11: .invisibility, 12: .light, 13: .unknown13,
        14: .unknown14, 15: .lock, 16: .open, 17: .boundWeapon,
        18: .summonCreature, 19: .detectLife, 20: .telekinesis, 21: .paralysis,
        22: .reanimate, 23: .soulTrap, 24: .turnUndead, 25: .guide,
        26: .werewolfFeed, 27: .cureParalysis, 28: .cureAddiction,
        29: .curePoison, 30: .concussion, 31: .valueAndParts,
        32: .accumulateMagnitude, 33: .stagger, 34: .peakValueModifier, 35: .cloak,
        36: .werewolf, 37: .slowTime, 38: .rally, 39: .enhanceWeapon,
        40: .spawnHazard, 41: .etherealize, 42: .banish,
        43: .spawnScriptedReference, 44: .disguise, 45: .grabActor,
        46: .vampireLord
    ]

    private static let rawValues = Dictionary(
        uniqueKeysWithValues: known.map { ($0.value, $0.key) }
    )

    private static let names: [UInt32: String] = [
        0: "value modifier", 1: "script", 2: "dispel", 3: "cure disease",
        4: "absorb", 5: "dual value modifier", 6: "calm", 7: "demoralize",
        8: "frenzy", 9: "disarm", 10: "command summoned", 11: "invisibility",
        12: "light", 13: "unknown 13", 14: "unknown 14", 15: "lock", 16: "open",
        17: "bound weapon", 18: "summon creature", 19: "detect life",
        20: "telekinesis", 21: "paralysis", 22: "reanimate", 23: "soul trap",
        24: "turn undead", 25: "guide", 26: "werewolf feed", 27: "cure paralysis",
        28: "cure addiction", 29: "cure poison", 30: "concussion",
        31: "value and parts", 32: "accumulate magnitude", 33: "stagger",
        34: "peak value modifier", 35: "cloak", 36: "werewolf", 37: "slow time",
        38: "rally", 39: "enhance weapon", 40: "spawn hazard", 41: "etherealize",
        42: "banish", 43: "spawn scripted ref", 44: "disguise", 45: "grab actor",
        46: "vampire lord"
    ]
}
