// STAT static: the model path a placed reference resolves to, relative to
// Data/ and looked up through the VFS. Layout: docs/formats/world-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct StaticObject: Sendable {
    public let formID: FormID
    public let editorID: String?
    /// MODL — mesh path relative to Data/ (e.g. "meshes\\clutter\\cup.nif").
    /// Nil for marker statics that have no model.
    public let modelPath: String?

    public init(record: ESMRecord) throws {
        guard record.type == "STAT" else {
            throw ESMError.malformed("expected STAT record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var modelPath: String?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "MODL":
                modelPath = try reader.readZString()
            default:
                break
            }
        }
        self.editorID = editorID
        self.modelPath = modelPath
    }
}
