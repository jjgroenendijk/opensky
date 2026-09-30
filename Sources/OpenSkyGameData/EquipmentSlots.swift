// What an equippable item occupies: biped slots for worn armor (`BodySlots`,
// from BOD2/BODT) and hands for a weapon. A conflict is an overlap in either.
// Hands come from the weapon's ETYP link through EQUP (`EquipSlotTable`), not
// from the animation type. See docs/formats/shouts-equip-slots.md,
// docs/engine/inventory-equipment.md, and docs/engine/inventory-state.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// The hands an equipped item takes. Not a biped slot: nothing in BOD2/BODT
/// describes holding something.
nonisolated public struct HandSlots: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let rightHand = HandSlots(rawValue: 1 << 0)
    public static let leftHand = HandSlots(rawValue: 1 << 1)
    public static let bothHands: HandSlots = [.rightHand, .leftHand]

    /// True when the two sets share at least one hand.
    public func overlaps(_ other: HandSlots) -> Bool {
        !isDisjoint(with: other)
    }
}

/// Everything one equipped item takes up, across both kinds of slot.
nonisolated public struct EquipmentOccupancy: Equatable, Sendable {
    public let slots: BodySlots
    public let hands: HandSlots

    /// Takes nothing — the reading for an item that is carryable but not
    /// wearable, such as a potion.
    public static let none = EquipmentOccupancy(slots: BodySlots(), hands: HandSlots())

    public init(slots: BodySlots = BodySlots(), hands: HandSlots = HandSlots()) {
        self.slots = slots
        self.hands = hands
    }

    /// True when the item occupies nothing at all, which is what makes it
    /// unequippable.
    public var isEmpty: Bool {
        slots.isEmpty && hands.isEmpty
    }

    /// True when the two items cannot be worn at the same time.
    ///
    /// Overlap in either half is a conflict, and an item that occupies nothing
    /// conflicts with nothing — including with itself, which is why `equip`
    /// refuses such an item outright instead of relying on this.
    public func conflicts(with other: Self) -> Bool {
        slots.overlaps(other.slots) || hands.overlaps(other.hands)
    }
}

/// One equippable base record reduced to what equipping needs from it.
nonisolated public struct EquippableItem: Equatable, Sendable {
    public let occupancy: EquipmentOccupancy
    /// WEAP MODL — the world model a hand attachment loads. Nil for armour,
    /// whose geometry comes from its ARMA armatures instead.
    public let modelPath: String?
}

/// Which slots each equippable base record in one plugin occupies. Single-plugin
/// and raw-FormID keyed. Separate from `ItemDefinitionStore`, which is the
/// inventory view and carries no body template.
nonisolated public struct EquipmentCatalog: Sendable {
    /// The hands a weapon takes when its ETYP link names nothing this plugin
    /// can resolve. Five vanilla WEAP records carry no ETYP at all — the
    /// unarmed pseudo-weapon among them — and the right hand is both what the
    /// retired animation-type heuristic returned for them and the hand the
    /// skeleton's `Weapon` attach node hangs off.
    public static let defaultWeaponHands = HandSlots.rightHand

    /// Equippable items by raw FormID: every ARMO with a body template, plus
    /// every WEAP.
    public let items: [UInt32: EquippableItem]
    /// The EQUP graph the ETYP links were resolved through, kept so an
    /// inspector can show which slot an item resolved to.
    public let equipSlots: EquipSlotTable
    /// How many WEAP records fell back on `defaultWeaponHands` because their
    /// ETYP was absent or named no EQUP in this plugin.
    public let unresolvedEquipTypes: Int
    /// ARMO and WEAP skips here, plus the EQUP skips of `equipSlots`.
    public let skippedRecords: SkippedRecords

    public init(
        items: [UInt32: EquippableItem],
        equipSlots: EquipSlotTable = EquipSlotTable(),
        unresolvedEquipTypes: Int = 0,
        skippedRecords: SkippedRecords = SkippedRecords()
    ) {
        self.items = items
        self.equipSlots = equipSlots
        self.unresolvedEquipTypes = unresolvedEquipTypes
        self.skippedRecords = skippedRecords.merging(equipSlots.skippedRecords)
    }

    /// Indexes the ARMO and WEAP top groups against the plugin's own EQUP
    /// records. Records that fail to decode drop out and later read as not
    /// equippable.
    public static func build(from file: ESMFile) -> EquipmentCatalog {
        let localized = file.isLocalized
        let equipSlots = EquipSlotTable(file: file)
        var items: [UInt32: EquippableItem] = [:]
        var unresolved = 0
        var skipped = SkippedRecords()
        for record in file.liveRecords(of: "ARMO", skipped: &skipped) {
            guard
                let armor = skipped.decode(
                    record,
                    using: { try Armor(record: $0, localized: localized) }
                )
            else { continue }
            items[armor.formID.rawValue] = EquippableItem(
                occupancy: EquipmentOccupancy(slots: armor.bodyTemplate?.slots ?? BodySlots()),
                modelPath: nil
            )
        }
        for record in file.liveRecords(of: "WEAP", skipped: &skipped) {
            guard
                let weapon = skipped.decode(
                    record,
                    using: { try Weapon(record: $0, localized: localized) }
                )
            else { continue }
            let resolved = equipSlots.hands(of: weapon.equipType)
            if resolved == nil {
                unresolved += 1
            }
            items[weapon.formID.rawValue] = EquippableItem(
                occupancy: EquipmentOccupancy(hands: resolved ?? defaultWeaponHands),
                modelPath: weapon.fields.modelPath
            )
        }
        return EquipmentCatalog(
            items: items,
            equipSlots: equipSlots,
            unresolvedEquipTypes: unresolved,
            skippedRecords: skipped
        )
    }

    /// `item`'s entry, or nil when no loaded plugin describes it as equippable.
    public func item(_ item: FormID) -> EquippableItem? {
        items[item.rawValue]
    }

    /// What `item` occupies; `.none` when nothing describes it, which reads as
    /// "not equippable" everywhere it is used.
    public func occupancy(of item: FormID) -> EquipmentOccupancy {
        items[item.rawValue]?.occupancy ?? .none
    }
}
