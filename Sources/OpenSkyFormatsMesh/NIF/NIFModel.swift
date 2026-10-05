// Flattens a parsed NIF into engine meshes: walks from the footer roots,
// composes local transforms, and decodes rigid or skinned BSTriShape leaves.
// Bad refs, cycles, or absurd depth throw `NIFError.malformed`, so the caller
// skips the asset. See docs/formats/nif.md "Scene graph -> engine mesh".

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated extension NIFFile {
    /// Max parent-chain depth. Vanilla statics nest a handful of levels;
    /// anything deeper is malformed or hostile, not a real asset.
    private static let maxSceneGraphDepth = 64

    /// Flattens the block tree into drawable meshes with model-space
    /// transforms and deduplicated material slots.
    public func model(skeleton: NIFSkeleton? = nil) throws -> Model {
        var flattener = try Flattener(file: self, skeleton: skeleton)
        for root in roots {
            try flattener.walk(from: root)
        }
        return Model(
            meshes: flattener.meshes,
            materials: flattener.materials,
            skippedShapeCount: flattener.skippedShapeCount,
            editorMarkerShapeCount: flattener.editorMarkerShapeCount
        )
    }

    public struct Flattener: Sendable {
        /// Dedup key: which shader/alpha property blocks a shape referenced.
        public struct SlotKey: Hashable, Sendable {
            public let shaderPropertyBlock: Int?
            public let alphaPropertyBlock: Int?
        }

        public let file: NIFFile
        public let hierarchy: NIFNodeHierarchy
        public let skeleton: NIFSkeleton?
        public var meshes: [Mesh] = []
        public var materials: [Material] = []
        public var slotIndexes: [SlotKey: Int] = [:]
        public var skippedShapeCount = 0
        public var editorMarkerShapeCount = 0

        /// Types that carry drawable geometry rather than children.
        public static let shapeTypes: Set = [
            "BSTriShape", "BSSubIndexTriShape", "BSDynamicTriShape"
        ]

        /// The name of editor-only geometry, such as the box of a lean marker.
        /// Vanilla marker meshes use it; docs/formats/nif.md.
        public static let editorMarkerName = "EditorMarker"

        public static func isEditorMarker(_ name: String?) -> Bool {
            name?.caseInsensitiveCompare(editorMarkerName) == .orderedSame
        }

        public init(file: NIFFile, skeleton: NIFSkeleton?) throws {
            self.file = file
            hierarchy = try NIFNodeHierarchy(file: file)
            self.skeleton = skeleton
        }

        public mutating func walk(from root: Int32) throws {
            var stack = NIFGraphStack(root: root)
            while let visit = stack.next() {
                guard visit.ref >= 0 else { continue } // -1 = null ref
                let index = Int(visit.ref)
                guard index < file.blocks.count else {
                    throw NIFError.malformed(
                        "block ref \(visit.ref) out of range (\(file.blocks.count) blocks)"
                    )
                }
                guard visit.depth <= NIFFile.maxSceneGraphDepth else {
                    throw NIFError.malformed(
                        "scene graph deeper than \(NIFFile.maxSceneGraphDepth)"
                    )
                }
                guard stack.enter(index) else {
                    throw NIFError.malformed("scene graph cycle at block \(index)")
                }

                let block = file.blocks[index]
                if NIFNode.traversedTypes.contains(block.typeName) {
                    guard let node = try drawableNode(block) else { continue }
                    guard !Self.isEditorMarker(node.object.name) else {
                        editorMarkerShapeCount += 1
                        continue
                    }
                    let world = visit.parent * node.object.localTransform
                    stack.push(
                        children: node.children,
                        parent: world,
                        depth: visit.depth + 1
                    )
                } else if Self.shapeTypes.contains(block.typeName) {
                    try appendShape(block: block, parent: visit.parent)
                }
                // Any other type is a leaf we do not draw (collision, shader
                // properties, controllers…): subtree ends.
            }
        }

        /// The node a traversed block contributes, or `nil` for a subtree the
        /// flatten deliberately drops.
        private func drawableNode(_ block: NIFFile.Block) throws -> NIFNode? {
            guard block.typeName == "BSMultiBoundNode" else {
                return try NIFNode(data: block.data, header: file.header)
            }
            let multi = try NIFMultiBoundNode(data: block.data, header: file.header)
            // Terrain LOD stores water in a sibling subtree. Water has its own
            // pipeline; drawing it as opaque geometry would cover land.
            guard multi.object.name?.uppercased() != "WATER" else { return nil }
            return NIFNode(object: multi.object, children: multi.children)
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
            guard !Self.isEditorMarker(shape.object.name) else {
                editorMarkerShapeCount += 1
                return
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

        public struct ShapeGeometry: Sendable {
            public let positions: [SIMD3<Float>]
            public let normals: [SIMD3<Float>]
            public let tangents: [SIMD3<Float>]
            public let bitangents: [SIMD3<Float>]
            public let uvs: [SIMD2<Float>]
            public let colors: [SIMD4<Float>]
            public let indices: [UInt16]
            public let skinning: MeshSkinning?
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
    /// all falls back to `Material.fallback`; that is legitimate
    /// content drawn by other paths. Out-of-range refs are malformed, same as the walk.
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
