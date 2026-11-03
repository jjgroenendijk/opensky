// Drops the triangles of hidden dismember partitions, the way the game hides a cut body
// part. Layout of the partitions: docs/formats/nif-skinning.md.

import Foundation

nonisolated extension Mesh {
    /// The mesh without the triangles of every partition `isHidden` names, or nil when
    /// no triangle is left. A mesh without partitions comes back unchanged.
    public func hidingBodyParts(where isHidden: (UInt16) -> Bool) -> Mesh? {
        guard let skinning, !skinning.bodyParts.isEmpty else { return self }
        let hidden = skinning.bodyParts.filter { isHidden($0.bodyPart) }
        guard !hidden.isEmpty else { return self }
        var kept: [UInt16] = []
        var parts: [MeshBodyPart] = []
        for part in skinning.bodyParts where !isHidden(part.bodyPart) {
            let range = part.indices.clamped(to: indices.indices)
            let start = kept.count
            kept.append(contentsOf: indices[range])
            parts.append(MeshBodyPart(bodyPart: part.bodyPart, indices: start ..< kept.count))
        }
        guard !kept.isEmpty else { return nil }
        return Mesh(
            name: name, transform: transform, positions: positions, normals: normals,
            tangents: tangents, bitangents: bitangents, uvs: uvs, colors: colors,
            indices: kept, materialSlot: materialSlot,
            skinning: skinning.withBodyParts(parts)
        )
    }
}

nonisolated extension MeshSkinning {
    /// The same skin over partitions `parts`.
    public func withBodyParts(_ parts: [MeshBodyPart]) -> MeshSkinning {
        MeshSkinning(
            weights: weights, boneIndices: boneIndices, bindPoseMatrices: bindPoseMatrices,
            boneNames: boneNames, rootParentToSkin: rootParentToSkin,
            skinToBoneMatrices: skinToBoneMatrices, bodyParts: parts
        )
    }
}

nonisolated extension Model {
    /// One side of a cut. A mesh without partitions stays only when `cut` keeps such
    /// meshes, so a piece drawn on both sides does not draw it twice.
    public func keeping(_ cut: DismemberCut) -> Model {
        Model(
            meshes: meshes.compactMap { mesh in
                guard mesh.skinning?.bodyParts.isEmpty == false else {
                    return cut.keepsUnpartitioned ? mesh : nil
                }
                return mesh.hidingBodyParts(where: cut.side.hides)
            },
            materials: materials,
            skippedShapeCount: skippedShapeCount,
            editorMarkerShapeCount: editorMarkerShapeCount
        )
    }
}

/// The part of a model one piece of a decapitated actor draws.
nonisolated public struct DismemberCut: Hashable, Sendable {
    public let side: DismemberSide
    /// Whether this piece owns the meshes that carry no partitions.
    public let keepsUnpartitioned: Bool

    public init(side: DismemberSide, keepsUnpartitioned: Bool) {
        self.side = side
        self.keepsUnpartitioned = keepsUnpartitioned
    }

    public var cacheKey: String {
        side.rawValue + (keepsUnpartitioned ? "+whole" : "")
    }
}

/// The side of a decapitation a model keeps. Body part IDs are nif.xml
/// `BSDismemberBodyPartType` values (docs/formats/nif-skinning.md).
nonisolated public enum DismemberSide: String, Equatable, Sendable {
    case body
    case head

    /// Head, hair, long hair, circlet, ears, face, face jewelry, and the head's neck gore,
    /// with their helmet and hood forms (130 to 150). 230, the neck, stays with the body.
    public static let headSideBodyParts: Set<UInt16> = [
        30, 31, 41, 42, 43, 44, 50, 55, 130, 131, 132, 141, 142, 143, 150
    ]

    public func hides(_ bodyPart: UInt16) -> Bool {
        (self == .body) == Self.headSideBodyParts.contains(bodyPart)
    }
}
