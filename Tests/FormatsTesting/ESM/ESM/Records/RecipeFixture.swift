// Synthetic COBJ records, shared by the decoder tests and the recipe store
// tests. Layout: docs/formats/recipes.md.

import Foundation

public enum RecipeFixture: Sendable {
    public static func recordBytes(
        formID: UInt32,
        editorID: String,
        components: [(item: UInt32, count: Int32)] = [],
        conditions: [Data] = [],
        createdObject: UInt32? = nil,
        workbenchKeyword: UInt32? = nil,
        createdCount: UInt16? = nil
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if !components.isEmpty {
            fields += InventoryFixture.formIDField("COCT", UInt32(components.count))
        }
        for component in components {
            var data = Data()
            data.appendUInt32(component.item)
            data.appendUInt32(UInt32(bitPattern: component.count))
            fields += ESMFixture.field("CNTO", data)
        }
        fields += conditions.reduce(Data(), +)
        if let createdObject {
            fields += InventoryFixture.formIDField("CNAM", createdObject)
        }
        if let workbenchKeyword {
            fields += InventoryFixture.formIDField("BNAM", workbenchKeyword)
        }
        if let createdCount {
            var data = Data()
            data.appendUInt16(createdCount)
            fields += ESMFixture.field("NAM1", data)
        }
        return ESMFixture.record("COBJ", formID: formID, data: fields)
    }
}
