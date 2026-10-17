// The change form envelope on the write side, and the reference encoder: the inverse of
// `ESSReferenceChange`. The change flags follow from the fields that are present.
// See docs/formats/ess-change-forms.md.

import Foundation

nonisolated extension ESSChangeForm {
    /// The version every Special Edition change form carries.
    public static let currentVersion: UInt8 = 74

    /// Uncompressed `data` with the narrowest length size that holds it.
    public init(form: ESSRefID, flags: UInt32, signature: String, data: Data) throws(ESSError) {
        guard let type = ESSChangeFormType(signature: signature) else {
            throw .invalidValue(context: "no change form type \(signature)")
        }
        let size = data.count <= 0xFF ? 1 : data.count <= 0xFFFF ? 2 : 4
        self.init(
            form: form, flags: flags, typeIndex: type.index, version: Self.currentVersion,
            data: ESSChangeFormData(stored: data, lengthSize: size)
        )
    }

    func write(into writer: inout ESSWriter) throws(ESSError) {
        let sizeBits: UInt8 = switch lengthSize {
        case 1: 0
        case 2: 1
        default: 2
        }
        let limit = lengthSize == 4 ? Int(UInt32.max) : (1 << (lengthSize * 8)) - 1
        guard storedData.count <= limit, Int(uncompressedLength) <= limit else {
            throw .invalidCount(context: "change form \(form) data", count: storedData.count)
        }
        writer.refID(form)
        writer.uint32(flags)
        writer.uint8(sizeBits << 6 | typeIndex & 0x3F)
        writer.uint8(version)
        for length in [UInt32(storedData.count), uncompressedLength] {
            switch lengthSize {
            case 1: writer.uint8(UInt8(length))
            case 2: writer.uint16(UInt16(length))
            default: writer.uint32(length)
            }
        }
        writer.bytes(storedData)
    }
}

nonisolated extension ESSReferenceChange {
    private typealias Flag = ESSChangeFlag.Reference

    /// A reference change to write. A created form needs a placement with a base.
    public init(
        form: ESSRefID, isActor: Bool, placement: ESSPlacement? = nil,
        formFlags: UInt32? = nil, baseObject: ESSRefID? = nil, scale: Float? = nil,
        extraData: ESSExtraDataList? = nil, inventory: [ESSInventoryItem]? = nil
    ) {
        self.form = form
        self.isActor = isActor
        self.placement = placement
        self.formFlags = formFlags
        self.baseObject = baseObject
        self.scale = scale
        self.extraData = extraData
        self.inventory = inventory
    }

    /// The change form that decodes back to this value.
    public func changeForm() throws(ESSError) -> ESSChangeForm {
        guard status.isComplete else {
            throw .invalidValue(context: "reference \(form) is only partly decoded")
        }
        var flags: UInt32 = 0
        let data = try ESSWriter.build { writer throws(ESSError) in
            try writeInitial(&writer, flags: &flags)
            if isActor {
                // Undocumented actor header; the reader skips it.
                writer.bytes(Data(count: 8))
            }
            if let formFlags {
                flags |= ESSChangeFlag.formFlags
                writer.uint32(formFlags)
                writer.uint16(0)
            }
            if let baseObject {
                flags |= Flag.baseObject
                writer.refID(baseObject)
            }
            if let scale {
                flags |= Flag.scale
                writer.float32(scale)
            }
            if let extraData {
                // Unconfirmed: which extra flag the game sets for alias instances.
                flags |= Flag.extraGameOnly
                try extraData.write(into: &writer)
            }
            if let inventory {
                flags |= Flag.inventory
                try Self.writeInventory(inventory, into: &writer)
            }
        }
        return try ESSChangeForm(
            form: form, flags: flags, signature: isActor ? "ACHR" : "REFR", data: data
        )
    }

    private func writeInitial(
        _ writer: inout ESSWriter, flags: inout UInt32
    ) throws(ESSError) {
        if form.kind == .created {
            guard let placement, let base = placement.createdBase else {
                throw .invalidValue(context: "created reference \(form) has no base")
            }
            writer.refID(placement.space)
            writer.vector3(placement.position)
            writer.vector3(placement.rotation)
            writer.uint8(0)
            writer.refID(base)
            return
        }
        guard let placement else { return }
        flags |= Flag.move
        writer.refID(placement.space)
        writer.vector3(placement.position)
        writer.vector3(placement.rotation)
    }

    private static func writeInventory(
        _ items: [ESSInventoryItem], into writer: inout ESSWriter
    ) throws(ESSError) {
        try writer.count(items.count, "inventory")
        for item in items {
            writer.refID(item.item)
            writer.int32(item.count)
            try writer.count(item.extraData.count, "inventory extra data")
            for list in item.extraData {
                try list.write(into: &writer)
            }
        }
    }
}
