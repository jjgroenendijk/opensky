// What the behavior graph's `iRightHandType` and `iLeftHandType` integers mean,
// read from this install: `weapequip.hkx` selector order, the state ids of
// `0_master.hkx`'s `MT_LeftHandOverride`, and the `1hm_behavior.hkx` conditions all
// agree. It matches WEAP DNAM only for 0-8: the graph has spell 9, shield 10,
// torch 11 and crossbow 12. `init(weapon:)` converts.
// See docs/engine/combat-graph-names.md.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsESM

/// One hand's contents as the behavior graph counts them.
///
/// `Int32` raw values, matching the `int32` the graph declares, so writing one
/// is `BehaviorVariableValue.int(handType.rawValue)` with no conversion.
nonisolated public enum CombatHandType: Int32, Equatable, Sendable, CaseIterable {
    /// Nothing held: the hand-to-hand animation set.
    case handToHand = 0
    case sword = 1
    case dagger = 2
    case axe = 3
    case mace = 4
    /// Greatsword — `2HC_Equip.hkx`, the "two-hand cutting" family.
    case greatsword = 5
    /// Battleaxes and warhammers together — `2HW_Equip.hkx`.
    case battleaxe = 6
    case bow = 7
    case staff = 8
    /// A readied spell rather than an item.
    case spell = 9
    case shield = 10
    case torch = 11
    case crossbow = 12

    /// The hand type a WEAP's DNAM animation type asks for. Nil reads as
    /// hand-to-hand. DNAM crossbow 9 becomes 12, so a raw-value cast is wrong.
    public init(weapon animationType: Weapon.AnimationType?) {
        switch animationType {
        case .oneHandSword: self = .sword
        case .oneHandDagger: self = .dagger
        case .oneHandAxe: self = .axe
        case .oneHandMace: self = .mace
        case .twoHandSword: self = .greatsword
        case .twoHandAxe: self = .battleaxe
        case .bow: self = .bow
        case .staff: self = .staff
        case .crossbow: self = .crossbow
        case .other, .none: self = .handToHand
        }
    }

    /// The value written into the graph variable.
    public var graphValue: BehaviorVariableValue {
        .int(rawValue)
    }

    /// Whether drawing this hand plays the magic-cast equip rather than the
    /// weapon equip. Only a readied spell does: a staff is equipped through
    /// `Weap_Equip_MSG` like any other weapon, as its index-8 child shows.
    public var drawsAsMagic: Bool {
        self == .spell
    }

    /// Whether this fills both hands in the animation graph, so the left hand
    /// reports the right's number (`1hm_behavior.hkx` blocks on 7 or 12). Item
    /// occupancy comes from `EquipmentCatalog` and can differ; they answer different questions.
    public var occupiesBothHands: Bool {
        switch self {
        case .greatsword, .battleaxe, .bow, .crossbow: true
        default: false
        }
    }

    /// How the melee readout names it.
    public var displayName: String {
        switch self {
        case .handToHand: "empty"
        case .sword: "one-handed sword"
        case .dagger: "dagger"
        case .axe: "war axe"
        case .mace: "mace"
        case .greatsword: "greatsword"
        case .battleaxe: "battleaxe or warhammer"
        case .bow: "bow"
        case .staff: "staff"
        case .spell: "spell"
        case .shield: "shield"
        case .torch: "torch"
        case .crossbow: "crossbow"
        }
    }
}
