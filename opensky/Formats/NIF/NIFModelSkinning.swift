// Bind-pose skin decode for the NIF flattener: resolve NiSkinInstance +
// NiSkinData + NiSkinPartition into engine MeshSkinning. Two influence-index
// spaces coexist in SSE (probed on SabreCat.nif): the top-level
// BSVertexDataSSE stream stores skin-instance-global bone indices, while the
// per-partition Bone Indices array stores palette-local indices remapped
// through the partition bone palette.
//
// Reference: NifTools nif.xml (NiSkinInstance, NiSkinData, NiSkinPartition,
// SkinPartition, BSVertexDataSSE) + public Gamebryo NiSkinInstance help.
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout + observed values in docs/formats/nif.md.

import Foundation
import simd

nonisolated extension NIFFile.Flattener {
    /// Gamebryo bind formula:
    /// rootParentToSkin * currentBoneToRootParent * skinToBoneBind.
    func resolveSkinnedGeometry(
        shape: NIFTriShape,
        usesNodeReferencePose: Bool
    ) throws -> ShapeGeometry {
        let instanceBlock = try block(at: Int(shape.skinRef))
        guard
            ["NiSkinInstance", "BSDismemberSkinInstance"]
                .contains(instanceBlock.typeName)
        else {
            throw NIFError.malformed("shape skin ref is not a skin instance")
        }
        let instance = try NIFSkinInstance(
            data: instanceBlock.data,
            isDismember: instanceBlock.typeName == "BSDismemberSkinInstance"
        )
        let dataBlock = try typedBlock(ref: instance.dataRef, type: "NiSkinData")
        let partitionBlock = try typedBlock(
            ref: instance.skinPartitionRef,
            type: "NiSkinPartition"
        )
        let skinData = try NIFSkinData(data: dataBlock.data)
        let partition = try NIFSkinPartition(
            data: partitionBlock.data,
            header: file.header,
            shapeVertexCount: shape.vertexCount > 0 ? shape.vertexCount : nil
        )
        guard skinData.bones.count == instance.boneRefs.count else {
            throw NIFError.malformed("skin data/instance bone counts differ")
        }

        // BSDynamicTriShape keeps positions in its appended Vector4 array,
        // while FaceGen's NiSkinPartition top-level stream keeps UVs,
        // normals, colors, and influences with the vertex bit clear.
        // Ordinary skinned BSTriShape keeps every array in the partition.
        let stored = partition.vertices
        let arrays = NIFTriShape.VertexArrays(
            positions: shape.positions.isEmpty ? stored.positions : shape.positions,
            uvs: shape.uvs.isEmpty ? stored.uvs : shape.uvs,
            normals: shape.normals.isEmpty ? stored.normals : shape.normals,
            tangents: shape.tangents.isEmpty ? stored.tangents : shape.tangents,
            bitangents: shape.bitangents.isEmpty ? stored.bitangents : shape.bitangents,
            colors: shape.colors.isEmpty ? stored.colors : shape.colors,
            boneWeights: shape.boneWeights.isEmpty
                ? stored.boneWeights : shape.boneWeights,
            boneIndices: shape.boneIndices.isEmpty
                ? stored.boneIndices : shape.boneIndices
        )
        let triangles = shape.indices.isEmpty
            ? partition.partitions.flatMap(\.triangleIndices) : shape.indices
        let skinning = try resolveSkinning(
            geometry: (arrays, triangles),
            partition: partition,
            instance: instance,
            data: skinData,
            usesNodeReferencePose: usesNodeReferencePose
        )
        return ShapeGeometry(
            positions: arrays.positions,
            normals: arrays.normals,
            tangents: arrays.tangents,
            bitangents: arrays.bitangents,
            uvs: arrays.uvs,
            colors: arrays.colors,
            indices: triangles,
            skinning: skinning
        )
    }

    private func resolveSkinning(
        geometry: (arrays: NIFTriShape.VertexArrays, triangles: [UInt16]),
        partition: NIFSkinPartition,
        instance: NIFSkinInstance,
        data: NIFSkinData,
        usesNodeReferencePose: Bool
    ) throws -> MeshSkinning {
        let arrays = geometry.arrays
        let triangles = geometry.triangles
        let vertexCount = arrays.positions.count
        let hasGlobalInfluences = arrays.boneWeights.count == vertexCount
            && arrays.boneIndices.count == vertexCount
        var accumulator = InfluenceAccumulator(
            vertexCount: vertexCount,
            arrays: arrays,
            hasGlobalInfluences: hasGlobalInfluences,
            boneCount: instance.boneRefs.count
        )
        for submesh in partition.partitions {
            try accumulator.add(submesh: submesh)
        }
        let remapped = accumulator.boneIndices
        let resolvedWeights = accumulator.weights
        guard triangles.allSatisfy({ remapped[Int($0)] != nil }) else {
            throw NIFError.malformed("drawn skin vertex is absent from partition maps")
        }
        let resolvedIndices = remapped.map { $0 ?? .zero }
        let weights = try resolvedWeights.map { try Self.normalizedWeights($0 ?? .zero) }
        let matrices = try bindPoseMatrices(
            instance: instance,
            data: data,
            usesNodeReferencePose: usesNodeReferencePose
        )
        return MeshSkinning(
            weights: weights,
            boneIndices: resolvedIndices,
            bindPoseMatrices: matrices,
            boneNames: boneNames(instance: instance),
            rootParentToSkin: data.rootParentToSkin.matrix,
            skinToBoneMatrices: data.bones.map(\.skinToBone.matrix)
        )
    }

    private func boneNames(instance: NIFSkinInstance) -> [String] {
        instance.boneRefs.map { reference in
            guard reference >= 0 else { return "" }
            return hierarchy.names[Int(reference)] ?? ""
        }
    }

    private static func normalizedWeights(_ value: SIMD4<Float>) throws -> SIMD4<Float> {
        let sum = value.x + value.y + value.z + value.w
        guard sum.isFinite, sum > .ulpOfOne else {
            throw NIFError.malformed("drawn skin vertex has zero total weight")
        }
        return value / sum
    }

    private func bindPoseMatrices(
        instance: NIFSkinInstance,
        data: NIFSkinData,
        usesNodeReferencePose: Bool
    ) throws -> [float4x4] {
        guard
            instance.skeletonRootRef >= 0,
            hierarchy.worldTransforms[Int(instance.skeletonRootRef)] != nil,
            abs(data.rootParentToSkin.matrix.determinant) > .ulpOfOne
        else {
            throw NIFError.malformed("skin skeleton root is unresolved or singular")
        }
        return try zip(instance.boneRefs, data.bones).map { boneRef, bone in
            guard boneRef >= 0 else {
                throw NIFError.malformed("skin bone node is unresolved")
            }
            let index = Int(boneRef)
            guard
                let nodeBoneToRootParent = hierarchy.worldTransforms[index],
                abs(bone.skinToBone.matrix.determinant) > .ulpOfOne
            else {
                throw NIFError.malformed("skin bone node is unresolved")
            }
            if let skeleton {
                guard
                    let name = hierarchy.names[index],
                    skeleton.boneTransforms[name] != nil
                else {
                    throw NIFError.malformed("skin bone is absent from skeleton")
                }
            }
            // FaceGen dynamic shapes keep some parts (notably mouth) in bone
            // space; their own NPC Head/Spine nodes carry current pose.
            // Ordinary body positions are already authored in bind space;
            // reconstructing current from inverse-bind preserves them.
            let currentBoneToRootParent = if usesNodeReferencePose {
                nodeBoneToRootParent
            } else {
                data.rootParentToSkin.matrix.inverse * bone.skinToBone.matrix.inverse
            }
            return data.rootParentToSkin.matrix
                * currentBoneToRootParent
                * bone.skinToBone.matrix
        }
    }

    private func typedBlock(ref: Int32, type: String) throws -> NIFFile.Block {
        guard ref >= 0 else {
            throw NIFError.malformed("missing \(type) ref")
        }
        let result = try block(at: Int(ref))
        guard result.typeName == type else {
            throw NIFError.malformed("block ref \(ref) is not \(type)")
        }
        return result
    }

    func block(at index: Int) throws -> NIFFile.Block {
        guard index < file.blocks.count else {
            throw NIFError.malformed(
                "block ref \(index) out of range (\(file.blocks.count) blocks)"
            )
        }
        return file.blocks[index]
    }
}

/// Merges each partition's per-vertex influences into shared global arrays,
/// honouring both SSE index spaces and detecting shared-vertex conflicts.
private struct InfluenceAccumulator {
    var boneIndices: [SIMD4<UInt16>?]
    var weights: [SIMD4<Float>?]
    let arrays: NIFTriShape.VertexArrays
    let hasGlobalInfluences: Bool
    let boneCount: Int

    init(
        vertexCount: Int,
        arrays: NIFTriShape.VertexArrays,
        hasGlobalInfluences: Bool,
        boneCount: Int
    ) {
        boneIndices = .init(repeating: nil, count: vertexCount)
        weights = .init(repeating: nil, count: vertexCount)
        self.arrays = arrays
        self.hasGlobalInfluences = hasGlobalInfluences
        self.boneCount = boneCount
    }

    mutating func add(submesh: NIFSkinPartition.Partition) throws {
        let hasLocalInfluences = submesh.vertexWeights.count == submesh.vertexMap.count
            && submesh.boneIndices.count == submesh.vertexMap.count
        guard hasGlobalInfluences || hasLocalInfluences else {
            throw NIFError.malformed("skinned vertex stream lacks four influences")
        }
        for (local, globalIndex) in submesh.vertexMap.enumerated() {
            let global = Int(globalIndex)
            let mapped: SIMD4<UInt16>
            let vertexWeights: SIMD4<Float>
            if hasGlobalInfluences {
                mapped = try Self.validateGlobalBoneIndices(
                    arrays.boneIndices[global],
                    boneCount: boneCount
                )
                vertexWeights = arrays.boneWeights[global]
            } else {
                mapped = try Self.remapBoneIndices(
                    submesh.boneIndices[local],
                    palette: submesh.bonePalette,
                    boneCount: boneCount
                )
                vertexWeights = submesh.vertexWeights[local]
            }
            if let prior = boneIndices[global], prior != mapped {
                throw NIFError.unsupported(
                    "shared skin vertex uses different partition palettes"
                )
            }
            if let prior = weights[global], prior != vertexWeights {
                throw NIFError.unsupported(
                    "shared skin vertex uses different partition weights"
                )
            }
            boneIndices[global] = mapped
            weights[global] = vertexWeights
        }
    }

    /// Validates already-global influence indices from the top-level SSE
    /// vertex stream. These index the skin instance's bone list directly,
    /// so there is no palette hop — only a bounds check against bone count.
    private static func validateGlobalBoneIndices(
        _ source: SIMD4<UInt16>,
        boneCount: Int
    ) throws -> SIMD4<UInt16> {
        for influence in 0 ..< 4 {
            guard Int(source[influence]) < boneCount else {
                throw NIFError.malformed("skin bone index out of range")
            }
        }
        return source
    }

    private static func remapBoneIndices(
        _ source: SIMD4<UInt16>,
        palette: [UInt16],
        boneCount: Int
    ) throws -> SIMD4<UInt16> {
        var result = SIMD4<UInt16>.zero
        for influence in 0 ..< 4 {
            let paletteIndex = Int(source[influence])
            guard paletteIndex < palette.count else {
                throw NIFError.malformed("vertex bone palette index out of range")
            }
            let bone = palette[paletteIndex]
            guard Int(bone) < boneCount else {
                throw NIFError.malformed("skin bone index out of range")
            }
            result[influence] = bone
        }
        return result
    }
}
