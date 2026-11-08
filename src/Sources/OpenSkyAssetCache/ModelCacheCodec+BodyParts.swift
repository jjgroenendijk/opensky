// The dismember partitions of a skinned mesh, read back with bounds checks.

import OpenSkyFormatsCore

nonisolated extension ModelCacheCodec {
    static func bodyParts(_ input: inout CachePayloadReader) throws -> [MeshBodyPart] {
        let count = try input.int()
        guard count >= 0, count <= Int(UInt16.max) else {
            throw CachePayloadError.badCount(count)
        }
        return try (0 ..< count).map { _ in
            let part = try input.int()
            let start = try input.int()
            let length = try input.int()
            guard
                (0 ... Int(UInt16.max)).contains(part), (0 ... Int(Int32.max)).contains(start),
                (0 ... Int(Int32.max)).contains(length)
            else {
                throw CachePayloadError.badCount(start)
            }
            return MeshBodyPart(bodyPart: UInt16(part), indices: start ..< start + length)
        }
    }
}
