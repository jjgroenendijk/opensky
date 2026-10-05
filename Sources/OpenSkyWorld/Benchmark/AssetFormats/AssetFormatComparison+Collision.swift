// Collision candidates: the NIF stored loose (parsed at load), and the shape
// arrays stored raw. Body settings such as filters and dynamics are small and
// are not part of the raw form, so only the geometry is compared.

import Foundation
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering
import simd

extension AssetFormatComparison {
    /// The element type of one raw collision blob.
    enum CollisionBlob {
        case vectors
        case indices
        case matrices

        func values(_ blob: Data) -> Int {
            switch self {
            case .vectors: PackedBlobs.values(blob, as: SIMD3<Float>.self).count
            case .indices: PackedBlobs.values(blob, as: UInt32.self).count
            case .matrices: PackedBlobs.values(blob, as: float4x4.self).count
            }
        }
    }

    func measureCollision(_ entry: AssetSampleEntry) throws -> AssetMeasurement {
        let source = try files.contents(forPath: entry.path)
        let original = try originalRow(entry, sourceBytes: source.count) {
            let (data, read) = try Self.timed { try files.contents(forPath: entry.path) }
            return try parseCollision(data, read: read)
        }
        let (model, parseMS) = try Self.timed { try NIFFile(data: source).collisionModel() }
        let ((types, blobs), blobMS) = Self.timed { Self.collisionBlobs(model) }
        let (packed, packMS) = Self.timed { PackedBlobs(blobs) }
        let convertMS = parseMS + blobMS + packMS
        let expectedValues = zip(types, blobs).map { $0.values($1) }.reduce(0, +)
        let shippedRows = cacheRows(
            candidate: "shipped", payload: source, paths: [.cpu], fidelity: .lossless
        ) { _, url, storage in
            let (data, read) = try Self.timed {
                try readCacheFile(url, storage, byteCount: source.count)
            }
            return try parseCollision(data, read: read)
        }
        let readyRows = cacheRows(
            candidate: "ready", payload: packed.bytes, convertMS: convertMS, paths: [.cpu],
            fidelity: .lossless
        ) { _, url, storage in
            let (data, read) = try Self.timed {
                try readCacheFile(url, storage, byteCount: packed.bytes.count)
            }
            let ((rebuilt, values), decode) = try Self.timed {
                let rebuilt = try packed.blobs(from: data)
                return (rebuilt, zip(types, rebuilt).map { $0.values($1) }.reduce(0, +))
            }
            return Sample(
                timing: AssetLoadTiming(readMS: read, decodeMS: decode, uploadMS: 0),
                memoryBytes: packed.bytes.count,
                mismatch: rebuilt == blobs && values == expectedValues
                    ? nil : "rebuilt collision arrays differ"
            )
        }
        return AssetMeasurement(
            entry: entry,
            detail: "\(model.bodies.count) bodies, \(model.shapeCount) shapes, "
                + "\(model.triangleCount) triangles",
            candidates: [original] + shippedRows + readyRows,
            workUnits: original.diskBytes
        )
    }

    private func parseCollision(_ data: Data, read: Double) throws -> Sample {
        let (model, decode) = try Self.timed { try NIFFile(data: data).collisionModel() }
        return Sample(
            timing: AssetLoadTiming(readMS: read, decodeMS: decode, uploadMS: 0),
            memoryBytes: Self.collisionBlobs(model).blobs.map(\.count).reduce(0, +)
        )
    }

    /// Per shape: its transform, then its geometry arrays. Primitive shapes store
    /// their sizes as one vector each.
    static func collisionBlobs(_ model: NIFCollisionModel)
        -> (types: [CollisionBlob], blobs: [Data])
    {
        var types: [CollisionBlob] = []
        var blobs: [Data] = []
        func add(_ type: CollisionBlob, _ blob: Data) {
            types.append(type)
            blobs.append(blob)
        }
        for shape in model.bodies.flatMap(\.shapes) {
            add(.matrices, PackedBlobs.blob([shape.transform]))
            switch shape.geometry {
            case let .triangleSoup(vertices, indices), let .convexVertices(vertices, indices):
                add(.vectors, PackedBlobs.blob(vertices))
                add(.indices, PackedBlobs.blob(indices))
            case let .box(halfExtents):
                add(.vectors, PackedBlobs.blob([halfExtents]))
            case let .sphere(radius):
                add(.vectors, PackedBlobs.blob([SIMD3<Float>(radius, 0, 0)]))
            case let .capsule(first, second, radius):
                add(.vectors, PackedBlobs.blob([first, second, SIMD3<Float>(radius, 0, 0)]))
            }
        }
        return (types, blobs)
    }
}
