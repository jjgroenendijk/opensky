// Turns an EQUP graph into `HandSlots`. Only LeftHand and RightHand leaves
// occupy a hand, read by editor ID; a choose-one slot prefers the right hand,
// and a link to no EQUP is a tallied miss (docs/formats/shouts-equip-slots.md).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public enum EquipSlotHands: Sendable {
    /// Editor ID of the leaf slot meaning the right hand.
    public static let rightHandEditorID = "righthand"
    /// Editor ID of the leaf slot meaning the left hand.
    public static let leftHandEditorID = "lefthand"
    /// Bounds a parent chain a mod has made cyclic. Vanilla chains are one
    /// link deep; eight is far past anything meaningful.
    public static let parentDepthCap = 8

    /// The hands `slot` occupies, following its parents through `lookup`.
    public static func hands(of slot: EquipSlot, lookup: (FormID) -> EquipSlot?) -> HandSlots {
        choice(of: slot, lookup: lookup).hands
    }

    /// The same walk, keeping whether the slot takes every hand it names or one
    /// of them. A spell needs this: `BothHands` and `EitherHand` differ only in
    /// the DATA "use all parents" byte.
    public static func choice(
        of slot: EquipSlot,
        lookup: (FormID) -> EquipSlot?
    ) -> EquipSlotHandChoice {
        choice(of: slot, lookup: lookup, depth: 0)
    }

    /// The hands the leaf slot named by `editorID` occupies.
    public static func leafHands(editorID: String?) -> HandSlots {
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

/// Whether an EQUP slot takes every hand it names (`BothHands`) or one of them
/// (`EitherHand`). A readied spell needs the difference, because the player
/// names the hand.
nonisolated public enum EquipSlotHandChoice: Equatable, Sendable {
    /// Every hand in the set is taken at once. A leaf slot and an all-parents
    /// slot both read this way, so `.fixed([])` is the honest answer for Voice
    /// and Potion: a resolved slot that takes no hand at all.
    case fixed(HandSlots)
    /// Exactly one of these hands is taken and the equipper chooses which.
    case choice(HandSlots)

    /// Every hand the slot could occupy, whichever reading applies. Not what a
    /// `.choice` slot actually fills — use `occupancy(preferring:)` for that.
    public var candidates: HandSlots {
        switch self {
        case let .fixed(hands), let .choice(hands): hands
        }
    }

    /// The one deterministic answer `hands(of:lookup:)` has always given: an
    /// all-parents slot fills everything it names, and a choose-one slot
    /// resolves to the right hand when the right hand is among its options,
    /// because that is the hand the skeleton's `Weapon` attach node hangs off.
    public var hands: HandSlots {
        switch self {
        case let .fixed(hands): hands
        case let .choice(hands): hands.contains(.rightHand) ? .rightHand : hands
        }
    }

    /// What the slot occupies when the equipper asks for `hand`, or nil when it
    /// cannot go there. A `.fixed` slot ignores the request; a `.choice` slot
    /// refuses a hand it does not offer.
    public func occupancy(preferring hand: HandSlots) -> HandSlots? {
        switch self {
        case let .fixed(hands): hands.isEmpty ? nil : hands
        case let .choice(hands): hands.overlaps(hand) ? hand : nil
        }
    }
}

/// The EQUP records of one plugin, keyed by raw FormID like `EquipmentCatalog`.
/// Vanilla ETYP links all point into Skyrim.esm; `EquipSlotStore` serves mods.
nonisolated public struct EquipSlotTable: Equatable, Sendable {
    public let slots: [UInt32: EquipSlot]
    public let skippedRecords: SkippedRecords

    public init(
        slots: [UInt32: EquipSlot] = [:],
        skippedRecords: SkippedRecords = SkippedRecords()
    ) {
        self.slots = slots
        self.skippedRecords = skippedRecords
    }

    public init(file: ESMFile) {
        self.init(loadOrder: LoadOrderPlugins(file: file))
    }

    public init(loadOrder: LoadOrderPlugins) {
        var skipped = SkippedRecords()
        let slots = loadOrder.indexRecords(of: "EQUP", skipped: &skipped) {
            try EquipSlot(record: $0)
        }
        self.init(slots: slots, skippedRecords: skipped)
    }

    /// The hands `id` occupies, or nil when no EQUP in this plugin answers the
    /// link. Nil and `[]` are different answers: nil is an unresolved link,
    /// `[]` is a slot that genuinely takes no hand, such as Voice.
    public func hands(of id: FormID?) -> HandSlots? {
        handChoice(of: id)?.hands
    }

    /// The same answer keeping the all-parents/choose-one distinction, for a
    /// caller that names the hand it wants.
    public func handChoice(of id: FormID?) -> EquipSlotHandChoice? {
        guard let id, !id.isNull, let slot = slots[id.rawValue] else { return nil }
        return EquipSlotHands.choice(of: slot) { slots[$0.rawValue] }
    }
}
