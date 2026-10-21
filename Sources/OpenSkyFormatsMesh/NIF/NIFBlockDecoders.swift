// Typed decoders for whole blocks, by block type. Each reads every byte of its
// block, so `openskycli gaps` can flag a block a decoder leaves bytes in, and the
// mesh preview can show any block's decoded value.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum NIFBlockDecoders: Sendable {
    public typealias Decode = @Sendable (inout BinaryReader, NIFHeader) throws -> any Sendable

    private static let all: [String: Decode] = extraData
        .merging(nodes) { first, _ in first }
        .merging(controllers) { first, _ in first }
        .merging(particles) { first, _ in first }
        .merging(collision) { first, _ in first }
        .merging(geometry) { first, _ in first }
        .merging(shaders) { first, _ in first }
        .merging(bounds) { first, _ in first }

    public static func decoder(for typeName: String) -> Decode? {
        all[typeName]
    }

    /// The decoded value of `block`, or nil when no whole-block decoder reads its type.
    /// Throws when the bytes do not fit the layout, or when bytes are left over.
    public static func decode(_ block: NIFFile.Block, header: NIFHeader) throws -> (any Sendable)? {
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
