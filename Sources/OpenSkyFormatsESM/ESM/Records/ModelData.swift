// A model group: MODL path, MODT texture hashes, and MODS alternate textures.
// Other model slots use the same layout under other tags (MOD2/MO2T/MO2S, ...).
// Layout and sources: docs/formats/records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ModelData: Equatable, Sendable {
    /// MODS entry: a texture set that replaces the textures of one shape.
    public struct AlternateTexture: Equatable, Sendable {
        /// The shape's name in the mesh.
        public let shapeName: String
        public let textureSet: FormID
        public let shapeIndex: Int32
    }

    /// Relative to `Data/meshes`.
    public let path: String
    /// MODT. Its layout changes with the form version, so the bytes stay raw.
    public let textureHashes: Data?
    public internal(set) var alternateTextures: [AlternateTexture]

    public init(
        path: String,
        textureHashes: Data? = nil,
        alternateTextures: [AlternateTexture] = []
    ) {
        self.path = path
        self.textureHashes = textureHashes
        self.alternateTextures = alternateTextures
    }

    /// A uint32 count, then per entry a uint32-length name, a TXST FormID, and an int32 index.
    static func alternateTextures(_ reader: inout BinaryReader) throws -> [AlternateTexture] {
        let count = try Int(reader.readUInt32())
        var entries: [AlternateTexture] = []
        for _ in 0 ..< count {
            let length = try Int(reader.readUInt32())
            let start = reader.offset
            guard let name = try TextDecoding.gameText.decode(reader.read(count: length)) else {
                throw BinaryReaderError.invalidString(offset: start)
            }
            try entries.append(AlternateTexture(
                shapeName: name,
                textureSet: reader.readFormID(),
                shapeIndex: reader.readInt32()
            ))
        }
        return entries
    }
}
