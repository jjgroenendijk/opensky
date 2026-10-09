// STAT static: the model path a placed reference resolves to, relative to
// Data/ and looked up through the VFS. Layout: docs/formats/world-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct StaticObject: Sendable {
    /// DNAM: the MATO laid over the static on faces within `maxAngle` of up.
    public struct DirectionalMaterial: Equatable, Sendable {
        /// Degrees, 30-120.
        public let maxAngle: Float
        public let material: FormID?
        /// SSE only.
        public let consideredSnow: Bool
    }

    public internal(set) var formID: FormID
    public let editorID: String?
    public let bounds: ObjectBounds?
    /// MODL group — mesh path relative to Data/ (e.g. "meshes\\clutter\\cup.nif"),
    /// texture hashes, and MODS alternate textures. Nil for marker statics.
    public internal(set) var model: ModelData?
    public internal(set) var directionalMaterial: DirectionalMaterial?
    /// MNAM — the four distant LOD mesh paths, level 0 first. Empty when absent.
    public let distantLODModels: [String]
    /// Placed for the editor or for scripts; the game does not draw it.
    public let isEditorMarker: Bool
    public let skipped: FieldTally

    public var modelPath: String? {
        model?.path
    }

    public init(record: ESMRecord) throws {
        var rest = try RecordFields(record: record, type: "STAT")
        formID = rest.formID
        isEditorMarker = record.isEditorMarker
        editorID = rest.editorID()
        bounds = rest.bounds()
        model = rest.model()
        directionalMaterial = rest.read("DNAM") { reader in
            try DirectionalMaterial(
                maxAngle: reader.readFloat32(),
                material: reader.readFormID().nonNull,
                consideredSnow: reader.bytesRemaining >= 1 && reader.readUInt8() != 0
            )
        }
        distantLODModels = rest.read("MNAM", Self.distantLODModels) ?? []
        skipped = rest.finish()
    }

    /// Four fixed 260-byte slots. Each holds a zstring; bytes after the
    /// terminator are leftover data.
    private static func distantLODModels(_ reader: inout BinaryReader) throws -> [String] {
        var paths: [String] = []
        while reader.bytesRemaining >= 260 {
            var slot = try BinaryReader(reader.read(count: 260))
            try paths.append(slot.readZString())
        }
        return paths
    }
}
