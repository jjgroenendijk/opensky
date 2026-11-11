// Typed decoders for whole blocks, by block type. Each reads every byte of its
// block, so `openskycli gaps` can flag a block a decoder leaves bytes in, and the
// mesh preview can show any block's decoded value.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum NIFBlockDecoders: Sendable {
    typealias Decode = @Sendable (inout BinaryReader, NIFHeader) throws -> any Sendable

    private static let all = joined([
        ExtraData.extraData, Nodes.nodes, Controllers.controllers, Particles.particles,
        Collision.collision, Geometry.geometry, Shaders.shaders, Bounds.bounds
    ])

    static var decodedTypeNames: Set<String> {
        Set(all.keys)
    }

    static func decoder(for typeName: String) -> Decode? {
        all[typeName]
    }

    /// Tables that share no block type; a shared one stops the table from building.
    static func joined(_ tables: [[String: Decode]]) -> [String: Decode] {
        Dictionary(uniqueKeysWithValues: tables.flatMap { table in
            table.map { ($0.key, $0.value) }
        })
    }

    /// The decoded value of `block`, or nil when no whole-block decoder reads its type.
    /// Throws when the bytes do not fit the layout, or when bytes are left over.
    public static func decode(_ block: NIFBlock, header: NIFHeader) throws -> (any Sendable)? {
        guard let decode = all[block.typeName] else { return nil }
        var reader = BinaryReader(block.data)
        let value = try decode(&reader, header)
        guard reader.bytesRemaining == 0 else {
            throw NIFError.malformed(
                "\(block.typeName) leaves \(reader.bytesRemaining) bytes unread"
            )
        }
        return value
    }
}
