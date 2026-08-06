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

    struct Flattener {
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
            let isShape = ["BSTriShape", "BSSubIndexTriShape", "BSDynamicTriShape"]
                .contains(block.typeName)
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
            } else if isShape {
                try appendShape(block: block, parent: parent)
            }
            // Any other type is a leaf we do not draw (collision, shader
            // properties, controllers…): subtree ends.
        }

        private mutating func appendShape(
            block: NIFFile.Block,
            parent: float4x4
        ) throws {
            let shape: NIFTriShape = switch block.typeName {
            case "BSSubIndexTriShape":
                try NIFSubIndexTriShape(data: block.data, header: file.header).shape
            case "BSDynamicTriShape":
                try NIFDynamicTriShape(data: block.data, header: file.header).shape
            default:
                try NIFTriShape(data: block.data, header: file.header)
            }
            let geometry = try resolveGeometry(
                shape: shape,
                usesNodeReferencePose: block.typeName == "BSDynamicTriShape"
            )
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

        struct ShapeGeometry {
            let positions: [SIMD3<Float>]
            let normals: [SIMD3<Float>]
            let tangents: [SIMD3<Float>]
            let bitangents: [SIMD3<Float>]
            let uvs: [SIMD2<Float>]
            let colors: [SIMD4<Float>]
            let indices: [UInt16]
            let skinning: MeshSkinning?
        }

        private func resolveGeometry(
            shape: NIFTriShape,
            usesNodeReferencePose: Bool
        ) throws -> ShapeGeometry {
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
            return try resolveSkinnedGeometry(
                shape: shape,
                usesNodeReferencePose: usesNodeReferencePose
            )
        }
    }
}

nonisolated extension NIFFile.Flattener {
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
}
