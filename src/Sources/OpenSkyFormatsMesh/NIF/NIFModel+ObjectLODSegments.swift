// Object LOD keeps every large reference of a block in one `BSSubIndexTriShape`. Its
// segments split that shape by cell, so the large-reference ring can hide one cell's part
// (docs/formats/lod.md, "Large references").

import Foundation
import OpenSkyFormatsCore

nonisolated extension NIFFile {
    /// The segments of a large-reference `BSSubIndexTriShape`; empty for any other shape.
    func largeReferenceSegments(
        of block: NIFFile.Block,
        at index: Int
    ) throws -> [NIFSubIndexTriShape.Segment] {
        guard block.typeName == "BSSubIndexTriShape" else { return [] }
        let isLargeReference = extraData(of: index).contains { extra in
            if case .largeReference(true) = extra.value {
                return true
            }
            return false
        }
        guard isLargeReference else { return [] }
        return try NIFSubIndexTriShape(data: block.data, header: header).segments
    }
}

nonisolated extension Mesh {
    /// One mesh per segment that holds triangles, each with only the vertices it uses.
    /// A skinned mesh, or one with fewer than two segments, stays whole.
    func splitByObjectLODSegment(_ segments: [NIFSubIndexTriShape.Segment]) -> [Mesh] {
        guard segments.count > 1, skinning == nil else { return [self] }
        return segments.enumerated().compactMap { number, segment in
            let start = Int(segment.startIndex)
            let end = start + Int(segment.primitiveCount) * 3
            guard segment.primitiveCount > 0, end <= indices.count else { return nil }
            return piece(indices: start ..< end, segment: number)
        }
    }

    private func piece(indices range: Range<Int>, segment: Int) -> Mesh {
        var remap: [UInt16: UInt16] = [:]
        var used: [Int] = []
        let local = indices[range].map { old in
            if let known = remap[old] {
                return known
            }
            let new = UInt16(used.count)
            remap[old] = new
            used.append(Int(old))
            return new
        }
        func pick<T>(_ values: [T]) -> [T] {
            values.isEmpty ? [] : used.map { values[$0] }
        }
        return Mesh(
            name: name, transform: transform, positions: pick(positions),
            normals: pick(normals), tangents: pick(tangents), bitangents: pick(bitangents),
            uvs: pick(uvs), colors: pick(colors), indices: local, materialSlot: materialSlot,
            objectLODSegment: segment
        )
    }
}
