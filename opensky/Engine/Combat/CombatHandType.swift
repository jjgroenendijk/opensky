// What the vanilla behavior graph's `iRightHandType` and `iLeftHandType`
// integers mean (issue #403).
//
// The M14 census gave both variables their names and their `int32` type but no
// encoding, so item 15.4 left them unwritten rather than guess which integer
// means "one-handed sword". This enum is the encoding, recovered from the
// user's own install rather than from memory or from a wiki. Three independent
// readings out of `meshes\actors\character\behaviors\` agree on it:
//
// 1. `weapequip.hkx` drives `hkbManualSelectorGenerator::m_selectedGeneratorIndex`
//    straight off `iRightHandType` on the equip selectors, so the child list of
//    `Weap_Equip_MSG` *is* the encoding, in order: index 0 selects the
//    hand-to-hand sub-selector, 1 `1HM_Equip.hkx`, 2 `Dag_Equip.hkx`, 3
//    `Axe_Equip.hkx`, 4 `Mac_Equip.hkx`, 5 `2HC_Equip.hkx`, 6 `2HW_Equip.hkx`,
//    7 `Bow_Equip.hkx`, 8 `Stf_Equip.hkx`, and 12
//    `DLC01\CrossBow_Equip.hkx`. The same file's `MagicForceEquipStanding_MSG`
//    separates the tail off `iLeftHandType`: 8 blends the staff, 9 the magic
//    hand alone, 10 `MRh_and_Shield_ForceEquipBlend`, and 11
//    `MRhAndTorchForceEquipBoneSwitch`.
// 2. `0_master.hkx` names the same thirteen values as the state ids of its
//    `MT_LeftHandOverride` machine: `MT_H2H_State` is 0, `MT_1HM_State` 1,
//    `MT_Dagger_State` 2, `MT_Axe_State` 3, `MT_Mace_State` 4, `MT_2HM_State`
//    5, `MT_2HW_State` 6, `MT_BowState` 7, `MT_Staff_State` 8,
//    `MT_Magic_State` 9, `MT_Shield_State` 10, `MT_Torch_State` 11, and
//    `MT_CrossBowState` 12.
// 3. The transition conditions agree where they overlap: `1hm_behavior.hkx`
//    takes `bowAttackStart` only when `iRightHandType == 7`, bashes with a bow
//    or a crossbow on `(iRightHandType == 7) || (iRightHandType == 12)`, refuses
//    `blockStart` when `(iLeftHandType != 7) && (iLeftHandType != 12)` fails,
//    dual-wields only when both hands sit in `1...4`, and `magicbehavior.hkx`
//    shouts on `(iRightHandType == 8) || (iRightHandType == 9)`.
//
// This is *not* the WEAP DNAM animation type, which is the trap here: the two
// agree on 0 through 8 and then diverge, because DNAM spells crossbow 9 while
// the graph spells spell 9 and crossbow 12, and the graph carries three values
// (spell, shield, torch) that no WEAP record can hold at all. `init(weapon:)`
// is that conversion and is the only place the two enums meet.
//
// Documented in docs/engine/melee-combat.md.

import Foundation

/// One hand's contents as the behavior graph counts them.
///
/// `Int32` raw values, matching the `int32` the graph declares, so writing one
/// is `BehaviorVariableValue.int(handType.rawValue)` with no conversion.
nonisolated enum CombatHandType: Int32, Equatable, Sendable, CaseIterable {
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

    /// The hand type a WEAP's DNAM animation type asks for.
    ///
    /// Nil — an unreadable or absent animation type — reads as hand-to-hand,
    /// which is what an actor with nothing resolved is holding. A DNAM
    /// `crossbow` is 9 in the record and 12 in the graph; every other value
    /// carries across unchanged, which is exactly why this conversion exists
    /// rather than a raw-value cast.
    init(weapon animationType: Weapon.AnimationType?) {
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
    var graphValue: BehaviorVariableValue {
        .int(rawValue)
    }

    /// Whether drawing this hand plays the magic-cast equip rather than the
    /// weapon equip. Only a readied spell does: a staff is equipped through
    /// `Weap_Equip_MSG` like any other weapon, as its index-8 child shows.
    var drawsAsMagic: Bool {
        self == .spell
    }

    /// Whether holding this fills both hands, so the left hand reports the same
    /// number as the right. `1hm_behavior.hkx` reads it that way: it refuses
    /// `blockStart` on `iLeftHandType == 7` or `12`, which is only ever true
    /// when a bow or a crossbow is what the *right* hand is holding.
    ///
    /// This is the animation graph's own notion of two-handedness, not the
    /// record's: `EquipmentCatalog` gets occupancy from the WEAP ETYP link and
    /// its EQUP graph instead, and the two disagree on the handful of vanilla
    /// weapons whose authored slot does not match their animation family.
    /// Nothing reconciles them, because they answer different questions —
    /// which animation set plays, and which hands the item fills.
    var occupiesBothHands: Bool {
        switch self {
        case .greatsword, .battleaxe, .bow, .crossbow: true
        default: false
        }
    }

    /// How the melee readout names it.
    var displayName: String {
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
