// Reference and actor change data: the initial block, flags, base object, scale, extra
// data, inventory, and animation. The rest of an actor's data is undocumented.
// See docs/formats/ess-change-forms.md#references.

import Foundation

nonisolated public struct ESSPlacement: Equatable, Sendable {
    /// The cell or worldspace the reference is in.
    public let space: ESSRefID
    public let position: SIMD3<Float>
    /// Radians, as in a plugin's placement.
    public let rotation: SIMD3<Float>
    /// The base object of a created reference, from initial type 5.
    public let createdBase: ESSRefID?
}

nonisolated public struct ESSInventoryItem: Equatable, Sendable {
    public let item: ESSRefID
    /// Change against the base container, so it may be negative.
    public let count: Int32
    /// One list per extra stack, such as a worn or enchanted copy.
    public let extraData: [ESSExtraDataList]

    public var isWorn: Bool {
        extraData.contains { $0.contains(22) || $0.contains(23) }
    }
}

nonisolated public struct ESSReferenceChange: Equatable, Sendable {
    public let form: ESSRefID
    public let isActor: Bool
    public internal(set) var placement: ESSPlacement?
    /// The form's runtime flags: `0x800` disabled and `0x20` deleted, as in a plugin.
    public internal(set) var formFlags: UInt32?
    public internal(set) var baseObject: ESSRefID?
    public internal(set) var scale: Float?
    public internal(set) var extraData: ESSExtraDataList?
    public internal(set) var inventory: [ESSInventoryItem]?
    public internal(set) var status = ESSDecodeStatus.complete

    public static let disabledFlag: UInt32 = 0x0000_0800
    public static let deletedFlag: UInt32 = 0x0000_0020

    public var isDisabled: Bool? {
        formFlags.map { $0 & Self.disabledFlag != 0 }
    }

    public var isDeleted: Bool? {
        formFlags.map { $0 & Self.deletedFlag != 0 }
    }

    private typealias Flag = ESSChangeFlag.Reference

    private static let objectExtraFlags: UInt32 = Flag.extraOwnership | Flag.promoted
        | Flag.extraActivatingChildren | Flag.extraEncounterZone | Flag.extraGameOnly
        | ESSChangeFlag.Object.extraLock | ESSChangeFlag.Object.extraAmmo
        | ESSChangeFlag.Object.doorExtraTeleport | ESSChangeFlag.Object.extraItemData

    private static let actorExtraFlags: UInt32 = Flag.extraOwnership | Flag.promoted
        | Flag.extraActivatingChildren | Flag.extraEncounterZone | Flag.extraCreatedOnly
        | Flag.extraGameOnly | ESSChangeFlag.Actor.extraPackageData
        | ESSChangeFlag.Actor.extraMerchantContainer | ESSChangeFlag.Actor.extraDismemberedLimbs
        | ESSChangeFlag.Actor.leveledActor

    public init(_ change: ESSChangeForm) throws(ESSError) {
        guard let type = change.type, type.isReference else {
            throw .invalidValue(context: "change form \(change.form) is not a reference")
        }
        form = change.form
        isActor = type.signature == "ACHR"
        var reader = try ESSReader(change.data())
        placement = try Self.readInitial(&reader, change: change)
        if change.has(Flag.havokMove) {
            try reader.skip(reader.count("havok data"), "havok data")
        }
        if isActor {
            try reader.skip(8, "actor header")
        }
        try readFlaggedFields(&reader, change: change)
        if status.isComplete, isActor, !reader.isAtEnd {
            status = .partial(blockedBy: "actor data after animation")
        } else if status.isComplete, !reader.isAtEnd {
            status = .partial(blockedBy: "\(reader.bytesRemaining) unread bytes")
        }
    }

    private mutating func readFlaggedFields(
        _ reader: inout ESSReader, change: ESSChangeForm
    ) throws(ESSError) {
        if change.has(ESSChangeFlag.formFlags) {
            formFlags = try reader.uint32("form flags")
            _ = try reader.uint16("form flags")
        }
        if change.has(Flag.baseObject) {
            baseObject = try reader.refID("base object")
        }
        if change.has(Flag.scale) {
            scale = try reader.float32("scale")
        }
        if change.flags & (isActor ? Self.actorExtraFlags : Self.objectExtraFlags) != 0 {
            let list = try ESSExtraDataList.read(&reader)
            extraData = list
            if let blocked = list.blockedBy {
                status = .partial(blockedBy: "extra data type \(blocked)")
                return
            }
        }
        if change.has(Flag.inventory) || change.has(Flag.leveledInventory) {
            let items = try Self.readInventory(&reader)
            inventory = items.items
            if let blocked = items.blockedBy {
                status = .partial(blockedBy: "inventory extra data type \(blocked)")
                return
            }
        }
        if change.has(Flag.animation) {
            try reader.skip(reader.count("animation"), "animation")
        }
    }

    /// The initial block's kind follows from the form and its flags (UESP "Initial type").
    private static func readInitial(
        _ reader: inout ESSReader, change: ESSChangeForm
    ) throws(ESSError) -> ESSPlacement? {
        if change.form.kind == .created {
            let space = try reader.refID("initial space")
            let position = try reader.vector3("initial position")
            let rotation = try reader.vector3("initial rotation")
            _ = try reader.uint8("initial created flag")
            let base = try reader.refID("initial base object")
            return ESSPlacement(
                space: space, position: position, rotation: rotation, createdBase: base
            )
        }
        let moved = change.has(Flag.move) || change.has(Flag.havokMove)
        let relocated = change.has(Flag.promoted) || change.has(Flag.cellChanged)
        guard moved || relocated else { return nil }
        let placement = try ESSPlacement(
            space: reader.refID("initial space"), position: reader.vector3("initial position"),
            rotation: reader.vector3("initial rotation"), createdBase: nil
        )
        if relocated {
            _ = try reader.refID("initial starting space")
            try reader.skip(4, "initial cell offsets")
        }
        return placement
    }

    private static func readInventory(
        _ reader: inout ESSReader
    ) throws(ESSError) -> (items: [ESSInventoryItem], blockedBy: UInt8?) {
        let count = try reader.count("inventory", minimumElementSize: 8)
        var items: [ESSInventoryItem] = []
        for _ in 0 ..< count {
            let item = try reader.refID("inventory item")
            let amount = try reader.int32("inventory count")
            let stacks = try reader.count("inventory extra data", minimumElementSize: 1)
            var lists: [ESSExtraDataList] = []
            for _ in 0 ..< stacks {
                let list = try ESSExtraDataList.read(&reader)
                lists.append(list)
                if let blocked = list.blockedBy {
                    items.append(ESSInventoryItem(item: item, count: amount, extraData: lists))
                    return (items, blocked)
                }
            }
            items.append(ESSInventoryItem(item: item, count: amount, extraData: lists))
        }
        return (items, nil)
    }
}
