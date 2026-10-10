// COBJ constructible object: one crafting recipe. It names the items it uses,
// the conditions that gate it, the workbench keyword, and what it makes.
// It is not an inventory item. Layout and sources: docs/formats/recipes.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ConstructibleObject: Equatable, Sendable {
    /// One CNTO: an item (or a FLST or LVLI of items) and how many the recipe uses.
    public struct Component: Equatable, Sendable {
        public let item: FormID
        public let count: Int32

        public init(item: FormID, count: Int32) {
            self.item = item
            self.count = count
        }
    }

    public let formID: FormID
    public let editorID: String?
    /// CNTO entries in file order.
    public let components: [Component]
    /// COCT as written. Diagnostics only; the CNTO run is the real list.
    public let declaredComponentCount: UInt32?
    public let conditions: ConditionList
    /// CNAM. Nil when absent or null.
    public let createdObject: FormID?
    /// BNAM, a KYWD that the crafting station carries.
    public let workbenchKeyword: FormID?
    /// NAM1. Nil when absent; the game then makes one.
    public let createdCount: UInt16?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        guard record.type == "COBJ" else {
            throw ESMError.malformed("expected COBJ record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var fields = Fields()
        for field in try record.fields() {
            do {
                if try !fields.conditions.decode(field: field), try !fields.decode(field) {
                    fields.skipped.note(.unknownField(field.type))
                }
            } catch {
                fields.skipped.note(.malformedField(field.type))
            }
        }
        editorID = fields.editorID
        components = fields.components
        declaredComponentCount = fields.declaredCount
        conditions = fields.conditions
        createdObject = fields.createdObject
        workbenchKeyword = fields.workbenchKeyword
        createdCount = fields.createdCount
        skipped = fields.skipped
    }

    /// The created count the game uses: NAM1, or one when NAM1 is absent.
    public var effectiveCreatedCount: Int {
        Int(createdCount ?? 1)
    }

    private struct Fields {
        var editorID: String?
        var components: [Component] = []
        var declaredCount: UInt32?
        var conditions = ConditionList()
        var createdObject: FormID?
        var workbenchKeyword: FormID?
        var createdCount: UInt16?
        var skipped = FieldTally()

        mutating func decode(_ field: ESMField) throws -> Bool {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID": editorID = try reader.readZString()
            case "COCT": declaredCount = try reader.readUInt32()
            case "CNTO":
                try components.append(Component(
                    item: FormID(reader.readUInt32()),
                    count: Int32(bitPattern: reader.readUInt32())
                ))
            case "CNAM": createdObject = try InventoryItemFields.optionalFormID(field)
            case "BNAM": workbenchKeyword = try InventoryItemFields.optionalFormID(field)
            case "NAM1": createdCount = try reader.readUInt16()
            default: return false
            }
            return true
        }
    }
}
