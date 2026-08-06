// WATR visual colors decoded into engine values. OpenSky deliberately reads
// only the three color fields needed by milestone 3.5; the rest of DNAM's
// water simulation parameters remain opaque.
//
// Reference: xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, WATR DNAM;
// UESP "Skyrim Mod:Mod File Format/WATR".
// Layout documented in docs/formats/records.md.

import Foundation
import simd

nonisolated struct WaterType {
    struct Colors: Equatable {
        let shallow: SIMD3<Float>
        let deep: SIMD3<Float>
        let reflection: SIMD3<Float>
    }

    let formID: FormID
    let editorID: String?
    /// DNAM colors. nil for absent or unknown-size DNAM variants.
    let colors: Colors?

    init(record: ESMRecord) throws {
        guard record.type == "WATR" else {
            throw ESMError.malformed("expected WATR record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var colors: Colors?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "DNAM":
                // SSE carries 228-byte and 232-byte variants. Both share the
                // first 52 bytes: ten floats, then shallow/deep/reflection
                // RGBX colors. Unknown variants are skipped, never guessed.
                guard field.data.count == 228 || field.data.count == 232 else { continue }
                _ = try reader.read(count: 40)
                colors = try Colors(
                    shallow: Self.readColor(&reader),
                    deep: Self.readColor(&reader),
                    reflection: Self.readColor(&reader)
                )
            default:
                break
            }
        }
        self.editorID = editorID
        self.colors = colors
    }

    private static func readColor(_ reader: inout BinaryReader) throws -> SIMD3<Float> {
        let red = try Float(reader.readUInt8()) / 255
        let green = try Float(reader.readUInt8()) / 255
        let blue = try Float(reader.readUInt8()) / 255
        _ = try reader.readUInt8() // RGBX padding
        return SIMD3(red, green, blue)
    }
}
