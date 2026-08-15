// What an equippable item occupies, and the index that answers it for one
// plugin (issue #178, roadmap item 12.2.1).
//
// Two disjoint kinds of occupancy exist and the engine needs both, so they
// travel together in one value:
//
// * Worn armour occupies biped object slots. ARMO carries them in BOD2/BODT
//   and `BodySlots` already models them; that is the same bitfield the
//   appearance pass masks skin against, so equipping reuses it rather than
//   inventing a parallel notion of "chest".
// * A weapon occupies hands, which are not biped slots at all. No bit of the
//   biped bitfield means "right hand" — slot 39 is the shield's *armour*, not
//   the hand holding it — so a second small set covers hands and a conflict is
//   an overlap in either half.
//
// Which hands a weapon takes comes from its ETYP link, read through the EQUP
// records of the same plugin (`EquipSlotTable`). That is the record the game
// itself uses, and it is the only one that separates the cases the DNAM
// animation type cannot: a staff and a bow share no animation family yet both
// resolve through EQUP, and the handful of vanilla weapons whose animation
// family disagrees with their authored slot follow the slot. The animation
// type is still decoded (#175) and still drives animation selection; it no
// longer decides occupancy.
//
// Documented in docs/formats/actors.md, docs/formats/magic-records.md,
// docs/engine/inventory-equipment.md and docs/engine/runtime-state.md.

import Foundation

/// The hands an equipped item takes. Not a biped slot: nothing in BOD2/BODT
/// describes holding something.
nonisolated struct HandSlots: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let rightHand = HandSlots(rawValue: 1 << 0)
    static let leftHand = HandSlots(rawValue: 1 << 1)
    static let bothHands: HandSlots = [.rightHand, .leftHand]

    /// True when the two sets share at least one hand.
    func overlaps(_ other: HandSlots) -> Bool {
        !isDisjoint(with: other)
    }
}

/// Everything one equipped item takes up, across both kinds of slot.
nonisolated struct EquipmentOccupancy: Equatable, Sendable {
    let slots: BodySlots
    let hands: HandSlots

    /// Takes nothing — the reading for an item that is carryable but not
    /// wearable, such as a potion.
    static let none = EquipmentOccupancy(slots: BodySlots(), hands: HandSlots())

    init(slots: BodySlots = BodySlots(), hands: HandSlots = HandSlots()) {
        self.slots = slots
        self.hands = hands
    }

    /// True when the item occupies nothing at all, which is what makes it
    /// unequippable.
    var isEmpty: Bool {
        slots.isEmpty && hands.isEmpty
    }

    /// True when the two items cannot be worn at the same time.
    ///
    /// Overlap in either half is a conflict, and an item that occupies nothing
    /// conflicts with nothing — including with itself, which is why `equip`
    /// refuses such an item outright instead of relying on this.
    func conflicts(with other: Self) -> Bool {
        slots.overlaps(other.slots) || hands.overlaps(other.hands)
    }
}

/// One equippable base record reduced to what equipping needs from it.
nonisolated struct EquippableItem: Equatable, Sendable {
    let formID: FormID
    let occupancy: EquipmentOccupancy
    /// WEAP MODL — the world model a hand attachment loads. Nil for armour,
    /// whose geometry comes from its ARMA armatures instead.
    let modelPath: String?
}

/// Which slots each equippable base record in one plugin occupies.
///
/// Single-plugin and raw-FormID keyed, matching `ItemDefinitionStore` and the
/// actor resolution indexes. Separate from `ItemDefinitionStore` because that
/// store's `ItemDefinition` is the *inventory* view — value, weight, name —
/// and deliberately carries no body template; widening it would put armour
/// layout data on every potion.
nonisolated struct EquipmentCatalog {
    /// The hands a weapon takes when its ETYP link names nothing this plugin
    /// can resolve. Five vanilla WEAP records carry no ETYP at all — the
    /// unarmed pseudo-weapon among them — and the right hand is both what the
    /// retired animation-type heuristic returned for them and the hand the
    /// skeleton's `Weapon` attach node hangs off.
    static let defaultWeaponHands = HandSlots.rightHand

    /// Equippable items by raw FormID: every ARMO with a body template, plus
    /// every WEAP.
    let items: [UInt32: EquippableItem]
    /// The EQUP graph the ETYP links were resolved through, kept so an
    /// inspector can show which slot an item resolved to.
    let equipSlots: EquipSlotTable
    /// How many WEAP records fell back on `defaultWeaponHands` because their
    /// ETYP was absent or named no EQUP in this plugin.
    let unresolvedEquipTypes: Int

    init(
        items: [UInt32: EquippableItem],
        equipSlots: EquipSlotTable = EquipSlotTable(),
        unresolvedEquipTypes: Int = 0
    ) {
        self.items = items
        self.equipSlots = equipSlots
        self.unresolvedEquipTypes = unresolvedEquipTypes
    }

    /// Indexes the ARMO and WEAP top groups against the plugin's own EQUP
    /// records. Records that fail to decode drop out and later read as not
    /// equippable.
    static func build(from file: ESMFile) -> EquipmentCatalog {
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let equipSlots = EquipSlotTable(file: file)
        var items: [UInt32: EquippableItem] = [:]
        var unresolved = 0
        for record in records(of: "ARMO", in: file) {
            guard let armor = try? Armor(record: record, localized: localized) else { continue }
            items[armor.formID.rawValue] = EquippableItem(
                formID: armor.formID,
                occupancy: EquipmentOccupancy(slots: armor.bodyTemplate?.slots ?? BodySlots()),
                modelPath: nil
            )
        }
        for record in records(of: "WEAP", in: file) {
            guard let weapon = try? Weapon(record: record, localized: localized) else { continue }
            let resolved = equipSlots.hands(of: weapon.equipType)
            if resolved == nil {
                unresolved += 1
            }
            items[weapon.formID.rawValue] = EquippableItem(
                formID: weapon.formID,
                occupancy: EquipmentOccupancy(hands: resolved ?? defaultWeaponHands),
                modelPath: weapon.fields.modelPath
            )
        }
        return EquipmentCatalog(
            items: items,
            equipSlots: equipSlots,
            unresolvedEquipTypes: unresolved
        )
    }

    /// `item`'s entry, or nil when no loaded plugin describes it as equippable.
    func item(_ item: FormID) -> EquippableItem? {
        items[item.rawValue]
    }

    /// What `item` occupies; `.none` when nothing describes it, which reads as
    /// "not equippable" everywhere it is used.
    func occupancy(of item: FormID) -> EquipmentOccupancy {
        items[item.rawValue]?.occupancy ?? .none
    }

    private static func records(of type: FourCC, in file: ESMFile) -> [ESMRecord] {
        guard let group = file.topGroup(of: type), let children = try? group.children() else {
            return []
        }
        return children.compactMap { child in
            guard case let .record(record) = child, record.type == type, !record.isDeleted else {
                return nil
            }
            return record
        }
    }
}
