// LTEX landscape texture: names the TXST that holds the texture paths.
// Layout and sources: docs/formats/land.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct LandTexture: Sendable {
    public let formID: FormID
    public let editorID: String?
    /// TNAM — the TXST texture set this landscape texture draws from.
    public let textureSet: FormID?
    /// MNAM: the MATT material of ground painted with this texture. Terrain is
    /// LAND, not a collision mesh, so it names its footstep material here.
    public let materialType: FormID?
    /// Repeated GNAM fields — GRAS records eligible where this LTEX contributes.
    public let grasses: [FormID]

    public init(record: ESMRecord) throws {
        guard record.type == "LTEX" else {
            throw ESMError.malformed("expected LTEX record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var textureSet: FormID?
        var materialType: FormID?
        var grasses: [FormID] = []
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "TNAM":
                textureSet = try FormID(reader.readUInt32())
            case "MNAM":
                guard field.data.count == 4 else { break }
                let id = try FormID(reader.readUInt32())
                materialType = id.isNull ? nil : id
            case "GNAM":
                try grasses.append(FormID(reader.readUInt32()))
            // Skipped: HNAM (havok friction/restitution), SNAM (texture
            // specular), INAM (SSE snow flag).
            default:
                break
            }
        }
        self.editorID = editorID
        self.textureSet = textureSet
        self.materialType = materialType
        self.grasses = grasses
    }
}

nonisolated extension LandTexture {
    /// A LAND layer with a null LTEX draws this LTEX (docs/formats/land.md).
    public static let nullFallbackEditorID = "LDirt02"

    /// Keys textures by raw FormID, with the null FormID keyed to the fallback.
    public static func index(_ textures: [LandTexture]) -> [UInt32: LandTexture] {
        var index: [UInt32: LandTexture] = [:]
        for texture in textures {
            index[texture.formID.rawValue] = texture
        }
        let fallback = textures.last {
            $0.editorID?.caseInsensitiveCompare(nullFallbackEditorID) == .orderedSame
        }
        if let fallback {
            index[0] = fallback
        }
        return index
    }
}
