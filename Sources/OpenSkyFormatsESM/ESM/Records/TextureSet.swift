// TXST texture set. Only the two maps terrain splatting needs are read.
// Layout and sources: docs/formats/land.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct TextureSet: Sendable {
    public let formID: FormID
    public let editorID: String?
    /// TX00 — diffuse map path relative to Data/ (e.g. "textures\\...\\x.dds").
    public let diffusePath: String?
    /// TX01 — normal/gloss map path.
    public let normalPath: String?

    public init(record: ESMRecord) throws {
        guard record.type == "TXST" else {
            throw ESMError.malformed("expected TXST record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var diffusePath: String?
        var normalPath: String?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "TX00":
                diffusePath = try reader.readZString()
            case "TX01":
                normalPath = try reader.readZString()
            // Skipped for now: TX02-TX07 (specular/env/height/etc. maps),
            // DODT (decal data), DNAM (texture set flags).
            default:
                break
            }
        }
        self.editorID = editorID
        self.diffusePath = diffusePath
        self.normalPath = normalPath
    }
}
