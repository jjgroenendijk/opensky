// Turns an EQUP graph into `HandSlots`, and indexes the EQUP records of one
// plugin so an ETYP link can be answered without a load-order index.
//
// The graph carries the structure but not the meaning: EQUP says that
// BothHands is "all of LeftHand and RightHand" and that EitherHand is "one of
// LeftHand or RightHand", and it says nothing at all about what LeftHand *is*.
// The leaves are named by the original engine, so OpenSky names them the same
// way — by editor ID, the only stable identifier a mod-added copy would also
// carry. A leaf whose editor ID is not one of the two hands (Voice, Potion, or
// anything a mod invents) occupies no hand, which is the right reading: a
// shout and a potion take no hand.
//
// Two policies are deliberate and both are visible to callers:
//
// * A choose-one slot resolves to the right hand when the right hand is among
//   its options. The game lets the player pick; the engine needs one
//   deterministic answer, and the right hand is the one the skeleton's
//   `Weapon` attach node hangs off.
// * A link that names no EQUP, or an EQUP that resolves to no hand at all
//   while the item is a weapon, is a tallied miss and the caller applies its
//   own documented default rather than silently dropping the item.
//
// Documented in docs/formats/magic-records.md and
// docs/engine/inventory-equipment.md.

import Foundation

nonisolated enum EquipSlotHands {
    /// Editor ID of the leaf slot meaning the right hand.
    static let rightHandEditorID = "righthand"
    /// Editor ID of the leaf slot meaning the left hand.
    static let leftHandEditorID = "lefthand"
    /// Bounds a parent chain a mod has made cyclic. Vanilla chains are one
    /// link deep; eight is far past anything meaningful.
    static let parentDepthCap = 8

    /// The hands `slot` occupies, following its parents through `lookup`.
    static func hands(of slot: EquipSlot, lookup: (FormID) -> EquipSlot?) -> HandSlots {
        hands(of: slot, lookup: lookup, depth: 0)
    }

    /// The hands the leaf slot named by `editorID` occupies.
    static func leafHands(editorID: String?) -> HandSlots {
        switch editorID?.lowercased() {
        case rightHandEditorID: .rightHand
        case leftHandEditorID: .leftHand
        default: []
        }
    }

    private static func hands(
        of slot: EquipSlot,
        lookup: (FormID) -> EquipSlot?,
        depth: Int
    ) -> HandSlots {
        guard depth < parentDepthCap else { return [] }
        guard !slot.parents.isEmpty else { return leafHands(editorID: slot.editorID) }
        let options = slot.parents.compactMap(lookup).map {
            hands(of: $0, lookup: lookup, depth: depth + 1)
        }
        if slot.usesAllParents {
            return options.reduce(into: HandSlots()) { $0.formUnion($1) }
        }
        if options.contains(where: { $0.contains(.rightHand) }) {
            return .rightHand
        }
        return options.first { !$0.isEmpty } ?? []
    }
}

/// The EQUP records of one plugin, keyed by raw FormID.
///
/// Single-plugin and raw-FormID keyed to match `EquipmentCatalog`, which is
/// built the same way; `EquipSlotStore` is the load-order-wide view for
/// inspectors. Every vanilla ETYP link points at an EQUP in Skyrim.esm, so the
/// single-file table answers the base game exactly, and a mod that adds its
/// own slots is served by the store.
nonisolated struct EquipSlotTable: Equatable {
    let slots: [UInt32: EquipSlot]

    init(slots: [UInt32: EquipSlot] = [:]) {
        self.slots = slots
    }

    init(file: ESMFile) {
        var slots: [UInt32: EquipSlot] = [:]
        guard
            let group = file.topGroup(of: "EQUP"),
            let children = try? group.children()
        else {
            self.init(slots: slots)
            return
        }
        for child in children {
            guard case let .record(record) = child, record.type == "EQUP", !record.isDeleted
            else { continue }
            guard let slot = try? EquipSlot(record: record) else { continue }
            slots[slot.formID.rawValue] = slot
        }
        self.init(slots: slots)
    }

    /// The hands `id` occupies, or nil when no EQUP in this plugin answers the
    /// link. Nil and `[]` are different answers: nil is an unresolved link,
    /// `[]` is a slot that genuinely takes no hand, such as Voice.
    func hands(of id: FormID?) -> HandSlots? {
        guard let id, !id.isNull, let slot = slots[id.rawValue] else { return nil }
        return EquipSlotHands.hands(of: slot) { slots[$0.rawValue] }
    }
}
