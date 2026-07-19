// Flatten a parsed NIF into engine Mesh/Model values: walk the scene graph
// from the footer roots, accumulate NiAVObject local transforms down the
// parent chain, decode rigid or bind-pose-skinned BSTriShape leaves.
// Animation, collision, particles and other non-drawable blocks are
// skipped. Defensive walk: out-of-range refs, ref
// cycles, and absurd depth throw NIFError.malformed — the caller skips the
// asset, the engine keeps running.
//
// Reference: NifTools nif.xml scene-graph semantics (NiNode children own
// the subtree; transforms compose parent-to-child).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// docs/formats/nif.md "Scene graph -> engine mesh".

import Foundation
import simd

nonisolated extension NIFFile {
    /// Max parent-chain depth. Vanilla statics nest a handful of levels;
    /// anything deeper is malformed or hostile, not a real asset.
    private static let maxSceneGraphDepth = 64

    /// Flattens the block tree into drawable meshes with model-space
    /// transforms and deduplicated material slots.
    func model(skeleton: NIFSkeleton? = nil) throws -> Model {
        var flattener = try Flattener(file: self, skeleton: skeleton)
        for root in roots {
            try flattener.visit(
                ref: root,
                parent: matrix_identity_float4x4,
                depth: 0
            )
        }
        return Model(
            meshes: flattener.meshes,
            materials: flattener.materials,
            skippedShapeCount: flattener.skippedShapeCount
        )
    }

    fileprivate struct Flattener {
        /// Dedup key: which shader/alpha property blocks a shape referenced.
        struct SlotKey: Hashable {
            let shaderPropertyBlock: Int?
            let alphaPropertyBlock: Int?
        }

        let file: NIFFile
        let hierarchy: NIFNodeHierarchy
        let skeleton: NIFSkeleton?
        var meshes: [Mesh] = []
        var materials: [Material] = []
        var slotIndexes: [SlotKey: Int] = [:]
        var skippedShapeCount = 0
        /// Recursion stack for cycle detection. A set, not a visited list:
        /// legitimate graphs may reuse a subtree under two parents.
        var pathStack: Set<Int> = []

        init(file: NIFFile, skeleton: NIFSkeleton?) throws {
            self.file = file
            hierarchy = try NIFNodeHierarchy(file: file)
            self.skeleton = skeleton
        }

        mutating func visit(ref: Int32, parent: float4x4, depth: Int) throws {
            guard ref >= 0 else { return } // -1 = null ref
            let index = Int(ref)
            guard index < file.blocks.count else {
                throw NIFError.malformed(
                    "block ref \(ref) out of range (\(file.blocks.count) blocks)"
                )
            }
            guard depth <= NIFFile.maxSceneGraphDepth else {
                throw NIFError.malformed(
                    "scene graph deeper than \(NIFFile.maxSceneGraphDepth)"
                )
            }
            guard pathStack.insert(index).inserted else {
                throw NIFError.malformed("scene graph cycle at block \(index)")
            }
            defer { pathStack.remove(index) }

            let block = file.blocks[index]
            if NIFNode.traversedTypes.contains(block.typeName) {
                let node: NIFNode
                if block.typeName == "BSMultiBoundNode" {
                    let multi = try NIFMultiBoundNode(data: block.data, header: file.header)
                    // Terrain LOD stores water in a sibling subtree. Water
                    // gets its own pipeline in milestone 3.5; drawing it as
                    // opaque geometry would cover land.
                    if multi.object.name?.uppercased() == "WATER" {
                        return
                    }
                    node = NIFNode(object: multi.object, children: multi.children)
                } else {
                    node = try NIFNode(data: block.data, header: file.header)
                }
                let world = parent * node.object.localTransform
                for child in node.children {
                    try visit(ref: child, parent: world, depth: depth + 1)
                }
            } else if block.typeName == "BSTriShape" || block.typeName == "BSSubIndexTriShape" {
                try appendShape(block: block, parent: parent)
            }
            // Any other type is a leaf we do not draw (collision, shader
            // properties, controllers, BSDynamicTriShape…): subtree ends.
        }

        private mutating func appendShape(
            block: NIFFile.Block,
            parent: float4x4
        ) throws {
            let shape = try block.typeName == "BSSubIndexTriShape"
                ? NIFSubIndexTriShape(data: block.data, header: file.header).shape
                : NIFTriShape(data: block.data, header: file.header)
            let geometry = try resolveGeometry(shape: shape)
            guard !geometry.positions.isEmpty, !geometry.indices.isEmpty else {
                skippedShapeCount += 1
                return
            }
            let key = SlotKey(
                shaderPropertyBlock: shape.shaderPropertyRef >= 0
                    ? Int(shape.shaderPropertyRef) : nil,
                alphaPropertyBlock: shape.alphaPropertyRef >= 0
                    ? Int(shape.alphaPropertyRef) : nil
            )
            let slotIndex: Int
            if let existing = slotIndexes[key] {
                slotIndex = existing
            } else {
                try materials.append(resolveMaterial(key: key))
                slotIndex = materials.count - 1
                slotIndexes[key] = slotIndex
            }
            meshes.append(Mesh(
                name: shape.object.name,
                transform: parent * shape.object.localTransform,
                positions: geometry.positions,
                normals: geometry.normals,
                tangents: geometry.tangents,
                bitangents: geometry.bitangents,
                uvs: geometry.uvs,
                colors: geometry.colors,
                indices: geometry.indices,
                materialSlot: slotIndex,
                skinning: geometry.skinning
            ))
        }

        private struct ShapeGeometry {
            let positions: [SIMD3<Float>]
            let normals: [SIMD3<Float>]
            let tangents: [SIMD3<Float>]
            let bitangents: [SIMD3<Float>]
            let uvs: [SIMD2<Float>]
            let colors: [SIMD4<Float>]
            let indices: [UInt16]
            let skinning: MeshSkinning?
        }

        private func resolveGeometry(shape: NIFTriShape) throws -> ShapeGeometry {
            guard shape.skinRef >= 0 else {
                return ShapeGeometry(
                    positions: shape.positions,
                    normals: shape.normals,
                    tangents: shape.tangents,
                    bitangents: shape.bitangents,
                    uvs: shape.uvs,
                    colors: shape.colors,
                    indices: shape.indices,
                    skinning: nil
                )
            }
            return try resolveSkinnedGeometry(shape: shape)
        }
    }
}

extension NIFFile.Flattener {
    /// Gamebryo bind formula:
    /// rootParentToSkin * currentBoneToRootParent * skinToBoneBind.
    /// Reference: NifTools nif.xml block layouts + public Gamebryo
    /// NiSkinInstance help, cited in docs/formats/nif.md.
    private func resolveSkinnedGeometry(
        shape: NIFTriShape
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
            header: file.header
        )
        guard skinData.bones.count == instance.boneRefs.count else {
            throw NIFError.malformed("skin data/instance bone counts differ")
        }

        let arrays = shape.positions.isEmpty
            ? partition.vertices : NIFTriShape.VertexArrays(
                positions: shape.positions,
                uvs: shape.uvs,
                normals: shape.normals,
                tangents: shape.tangents,
                bitangents: shape.bitangents,
                colors: shape.colors,
                boneWeights: shape.boneWeights,
                boneIndices: shape.boneIndices
            )
        let triangles = shape.indices.isEmpty
            ? partition.partitions.flatMap(\.triangleIndices) : shape.indices
        let skinning = try resolveSkinning(
            arrays: arrays,
            triangles: triangles,
            partition: partition,
            instance: instance,
            data: skinData
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
        arrays: NIFTriShape.VertexArrays,
        triangles: [UInt16],
        partition: NIFSkinPartition,
        instance: NIFSkinInstance,
        data: NIFSkinData
    ) throws -> MeshSkinning {
        let vertexCount = arrays.positions.count
        guard
            arrays.boneWeights.count == vertexCount,
            arrays.boneIndices.count == vertexCount
        else {
            throw NIFError.malformed("skinned vertex stream lacks four influences")
        }
        var remapped = [SIMD4<UInt16>?](repeating: nil, count: vertexCount)
        for submesh in partition.partitions {
            for (local, globalIndex) in submesh.vertexMap.enumerated() {
                let global = Int(globalIndex)
                let source = arrays.boneIndices[global]
                var mapped = SIMD4<UInt16>.zero
                for influence in 0 ..< 4 {
                    let paletteIndex = Int(source[influence])
                    guard paletteIndex < submesh.bonePalette.count else {
                        throw NIFError.malformed("vertex bone palette index out of range")
                    }
                    let bone = submesh.bonePalette[paletteIndex]
                    guard Int(bone) < instance.boneRefs.count else {
                        throw NIFError.malformed("skin bone index out of range")
                    }
                    mapped[influence] = bone
                }
                if let prior = remapped[global], prior != mapped {
                    throw NIFError.unsupported(
                        "shared skin vertex uses different partition palettes"
                    )
                }
                remapped[global] = mapped
                // Partition arrays duplicate top-level hardware data.
                // Reading them above proves their layout; global stream
                // remains source of truth for one GPU vertex buffer.
                _ = local
            }
        }
        guard triangles.allSatisfy({ remapped[Int($0)] != nil }) else {
            throw NIFError.malformed("drawn skin vertex is absent from partition maps")
        }
        let resolvedIndices = remapped.map { $0 ?? .zero }
        let weights = try arrays.boneWeights.map(Self.normalizedWeights)
        let matrices = try bindPoseMatrices(instance: instance, data: data)
        return MeshSkinning(
            weights: weights,
            boneIndices: resolvedIndices,
            bindPoseMatrices: matrices
        )
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
        data: NIFSkinData
    ) throws -> [float4x4] {
        guard
            instance.skeletonRootRef >= 0,
            hierarchy.worldTransforms[Int(instance.skeletonRootRef)] != nil,
            abs(data.rootParentToSkin.matrix.determinant) > .ulpOfOne
        else {
            throw NIFError.malformed("skin skeleton root is unresolved or singular")
        }
        return try zip(instance.boneRefs, data.bones).map { boneRef, bone in
            guard
                boneRef >= 0,
                hierarchy.worldTransforms[Int(boneRef)] != nil,
                abs(bone.skinToBone.matrix.determinant) > .ulpOfOne
            else {
                throw NIFError.malformed("skin bone node is unresolved")
            }
            let index = Int(boneRef)
            if let skeleton {
                guard
                    let name = hierarchy.names[index],
                    skeleton.boneTransforms[name] != nil
                else {
                    throw NIFError.malformed("skin bone is absent from skeleton")
                }
            }
            // Bind-only current pose comes from this skin's inverse-bind
            // data. Vanilla body dummy nodes omit translations; external
            // skeleton resolves/validates bone identities, but its ref
            // pose may differ from this mesh's authored bind pose.
            let currentBoneToRootParent = data.rootParentToSkin.matrix.inverse
                * bone.skinToBone.matrix.inverse
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

    /// Resolves a shape's property refs into an engine Material.
    /// A ref to a non-lighting shader (effect/water/sky) or no ref at
    /// all falls back to `Material.fallback` — legitimate content, out
    /// of M2 scope. Out-of-range refs are malformed, same as the walk.
    private func resolveMaterial(key: SlotKey) throws -> Material {
        var shader: NIFLightingShaderProperty?
        var textures: NIFShaderTextureSet?
        var alpha: NIFAlphaProperty?

        if let index = key.shaderPropertyBlock {
            let block = try block(at: index)
            if block.typeName == "BSLightingShaderProperty" {
                let property = try NIFLightingShaderProperty(
                    data: block.data,
                    header: file.header
                )
                shader = property
                if property.textureSetRef >= 0 {
                    let setBlock = try self.block(at: Int(property.textureSetRef))
                    if setBlock.typeName == "BSShaderTextureSet" {
                        textures = try NIFShaderTextureSet(
                            data: setBlock.data,
                            header: file.header
                        )
                    }
                }
            }
        }
        if let index = key.alphaPropertyBlock {
            let block = try block(at: index)
            if block.typeName == "NiAlphaProperty" {
                alpha = try NIFAlphaProperty(
                    data: block.data,
                    header: file.header
                )
            }
        }

        let fallback = Material.fallback
        return Material(
            diffuseTexture: textures?.diffusePath,
            normalTexture: textures?.normalPath,
            uvOffset: shader?.uvOffset ?? fallback.uvOffset,
            uvScale: shader?.uvScale ?? fallback.uvScale,
            alpha: shader?.alpha ?? fallback.alpha,
            glossiness: shader?.glossiness ?? fallback.glossiness,
            specularColor: shader?.specularColor ?? fallback.specularColor,
            specularStrength: shader?.specularStrength
                ?? fallback.specularStrength,
            doubleSided: shader?.isDoubleSided ?? false,
            alphaBlend: alpha?.blendEnabled ?? false,
            alphaTestThreshold: (alpha?.testEnabled ?? false)
                ? alpha?.testThreshold : nil
        )
    }

    private func block(at index: Int) throws -> NIFFile.Block {
        guard index < file.blocks.count else {
            throw NIFError.malformed(
                "block ref \(index) out of range (\(file.blocks.count) blocks)"
            )
        }
        return file.blocks[index]
    }
}
