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
        choice(of: slot, lookup: lookup).hands
    }

    /// The same walk, keeping the distinction `hands(of:lookup:)` collapses:
    /// whether the slot takes every hand it names or lets the equipper pick one
    /// of them.
    ///
    /// A spell needs the distinction and a weapon does not. `BothHands` and
    /// `EitherHand` name the same two parents and differ only in the DATA
    /// "use all parents" byte, so a master spell filling both hands and a
    /// novice spell going into whichever hand the player asked for are the same
    /// walk with two different readings of the answer (issue #470).
    static func choice(
        of slot: EquipSlot,
        lookup: (FormID) -> EquipSlot?
    ) -> EquipSlotHandChoice {
        choice(of: slot, lookup: lookup, depth: 0)
    }

    /// The hands the leaf slot named by `editorID` occupies.
    static func leafHands(editorID: String?) -> HandSlots {
        switch editorID?.lowercased() {
        case rightHandEditorID: .rightHand
        case leftHandEditorID: .leftHand
        default: []
        }
    }

    private static func choice(
        of slot: EquipSlot,
        lookup: (FormID) -> EquipSlot?,
        depth: Int
    ) -> EquipSlotHandChoice {
        guard depth < parentDepthCap else { return .fixed([]) }
        guard !slot.parents.isEmpty else {
            return .fixed(leafHands(editorID: slot.editorID))
        }
        let options = slot.parents.compactMap(lookup).reduce(into: HandSlots()) {
            $0.formUnion(choice(of: $1, lookup: lookup, depth: depth + 1).hands)
        }
        return slot.usesAllParents ? .fixed(options) : .choice(options)
    }
}

/// What an EQUP slot says about hand occupancy: every hand it names, or one of
/// them.
///
/// The two readings exist because EQUP encodes them in one graph. `BothHands`
/// lists LeftHand and RightHand with "use all parents" set and takes both;
/// `EitherHand` lists the same two with the byte clear and takes exactly one,
/// the equipper's pick. A weapon never needed the distinction — the engine has
/// to answer with one deterministic hand either way — but a readied spell does,
/// because the player names the hand.
nonisolated enum EquipSlotHandChoice: Equatable, Sendable {
    /// Every hand in the set is taken at once. A leaf slot and an all-parents
    /// slot both read this way, so `.fixed([])` is the honest answer for Voice
    /// and Potion: a resolved slot that takes no hand at all.
    case fixed(HandSlots)
    /// Exactly one of these hands is taken and the equipper chooses which.
    case choice(HandSlots)

    /// Every hand the slot could occupy, whichever reading applies. Not what a
    /// `.choice` slot actually fills — use `occupancy(preferring:)` for that.
    var candidates: HandSlots {
        switch self {
        case let .fixed(hands), let .choice(hands): hands
        }
    }

    /// The one deterministic answer `hands(of:lookup:)` has always given: an
    /// all-parents slot fills everything it names, and a choose-one slot
    /// resolves to the right hand when the right hand is among its options,
    /// because that is the hand the skeleton's `Weapon` attach node hangs off.
    var hands: HandSlots {
        switch self {
        case let .fixed(hands): hands
        case let .choice(hands): hands.contains(.rightHand) ? .rightHand : hands
        }
    }

    /// What the slot occupies when the equipper asks for `hand`, or nil when
    /// this slot cannot go there.
    ///
    /// A `.fixed` slot ignores the request and answers with everything it
    /// names, which is what makes a master spell fill both hands whichever hand
    /// the player pressed. A `.choice` slot answers with the requested hand
    /// when it is one of the options and refuses otherwise, rather than
    /// silently putting the spell somewhere else.
    func occupancy(preferring hand: HandSlots) -> HandSlots? {
        switch self {
        case let .fixed(hands): hands.isEmpty ? nil : hands
        case let .choice(hands): hands.overlaps(hand) ? hand : nil
        }
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
        handChoice(of: id)?.hands
    }

    /// The same answer keeping the all-parents/choose-one distinction, for a
    /// caller that names the hand it wants (issue #470).
    func handChoice(of id: FormID?) -> EquipSlotHandChoice? {
        guard let id, !id.isNull, let slot = slots[id.rawValue] else { return nil }
        return EquipSlotHands.choice(of: slot) { slots[$0.rawValue] }
    }
}
