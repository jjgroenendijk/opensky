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
        /// The block index of each mesh, in `meshes` order.
        public var meshBlocks: [Int] = []
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
                if
                    NIFNode.traversedTypes.contains(block.typeName)
                    || block.typeName == NIFSwitchNode.typeName
                {
                    guard let node = try drawableNode(block) else { continue }
                    guard !node.object.isHidden else { continue }
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
                    try appendShape(block: block, index: index, parent: visit.parent)
                }
                // Any other type is a leaf we do not draw (collision, shader
                // properties, controllers…): subtree ends.
            }
        }

        /// The node a traversed block contributes, or `nil` for a subtree the
        /// flatten deliberately drops.
        private func drawableNode(_ block: NIFFile.Block) throws -> NIFNode? {
            if block.typeName == NIFSwitchNode.typeName {
                return try NIFSwitchNode(data: block.data, header: file.header).activeNode
            }
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
            index: Int,
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
            guard !shape.object.isHidden, try !isUndrawableShape(shape) else {
                skippedShapeCount += 1
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
            try meshes.append(Mesh(
                name: shape.object.name,
                transform: parent * shape.object.localTransform,
                positions: geometry.positions,
                normals: geometry.normals,
                tangents: geometry.tangents,
                bitangents: geometry.bitangents,
                uvs: geometry.uvs,
                colors: opacityColours(geometry.colors, shape: shape),
                indices: geometry.indices,
                materialSlot: slotIndex,
                skinning: geometry.skinning
            ))
            meshBlocks.append(index)
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
    /// Resolves a shape's property refs into an engine Material. A water shader gives
    /// `Material.waterSurface`. A sky shader, an undecodable effect, or no ref gives
    /// `Material.fallback`.
    /// Out-of-range refs are malformed, same as the walk.
    private func resolveMaterial(key: SlotKey) throws -> Material {
        var shader: NIFLightingShaderProperty?
        var textures: NIFShaderTextureSet?

        if let index = key.shaderPropertyBlock {
            let block = try block(at: index)
            if
                block.typeName == NIFFile.effectShaderType,
                let material = try? effectMaterial(
                    block: block,
                    alphaBlock: key.alphaPropertyBlock
                )
            {
                return material
            }
            if block.typeName == NIFFile.waterShaderType {
                return .waterSurface
            }
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
        let alpha = try alphaProperty(at: key.alphaPropertyBlock)

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

nonisolated extension NIFFile {
    static let effectShaderType = "BSEffectShaderProperty"
    static let waterShaderType = "BSWaterShaderProperty"
}

nonisolated extension NIFFile.Flattener {
    /// The static path has no additive blend, no texture-less effect look, and no
    /// refraction, so those shapes are skipped. Drawn anyway, an effect shows as a flat
    /// card and a heat-haze dome shows its normal map as colour.
    /// A tree-animated shape's vertex alpha is wind weight, so it must not cut the branches.
    func opacityColours(_ colours: [SIMD4<Float>], shape: NIFTriShape) throws -> [SIMD4<Float>] {
        guard shape.shaderPropertyRef >= 0 else { return colours }
        let block = try block(at: Int(shape.shaderPropertyRef))
        guard
            block.typeName == "BSLightingShaderProperty",
            try NIFLightingShaderProperty(data: block.data, header: file.header).isTreeAnimated
        else { return colours }
        return colours.map { SIMD4($0.x, $0.y, $0.z, 1) }
    }

    func isUndrawableShape(_ shape: NIFTriShape) throws -> Bool {
        guard shape.shaderPropertyRef >= 0 else { return false }
        let block = try block(at: Int(shape.shaderPropertyRef))
        if block.typeName == "BSLightingShaderProperty" {
            return try NIFLightingShaderProperty(data: block.data, header: file.header).isRefraction
        }
        guard
            block.typeName == NIFFile.effectShaderType,
            let effect = try? NIFEffectShaderProperty(data: block.data, header: file.header)
        else { return false }
        let alphaRef = shape.alphaPropertyRef >= 0 ? Int(shape.alphaPropertyRef) : nil
        let isAdditive = try alphaProperty(at: alphaRef)?.isAdditive ?? false
        return effect.sourceTexturePath == nil || isAdditive
    }

    /// The static path draws an effect shape unlit, with its source texture,
    /// palette, and alpha property. Additive blending is not modeled.
    func effectMaterial(block: NIFFile.Block, alphaBlock: Int?) throws -> Material {
        let effect = try NIFEffectShaderProperty(data: block.data, header: file.header)
        let alpha = try alphaProperty(at: alphaBlock)
        let fallback = Material.fallback
        let shading = EffectShading(
            baseColor: effect.baseColor,
            baseColorScale: effect.baseColorScale,
            paletteTexture: effect.greyscaleTexturePath,
            paletteColor: effect.usesGreyscaleToPaletteColor,
            paletteAlpha: effect.usesGreyscaleToPaletteAlpha,
            falloff: effect.usesFalloff ? SIMD4(
                effect.falloffStartAngle, effect.falloffStopAngle,
                effect.falloffStartOpacity, effect.falloffStopOpacity
            ) : nil,
            vertexColors: effect.hasVertexColors,
            vertexAlpha: effect.hasVertexAlpha
        )
        return Material(
            diffuseTexture: effect.sourceTexturePath,
            normalTexture: nil,
            uvOffset: effect.uvOffset,
            uvScale: effect.uvScale,
            alpha: fallback.alpha,
            glossiness: fallback.glossiness,
            specularColor: fallback.specularColor,
            specularStrength: 0,
            doubleSided: effect.isDoubleSided,
            alphaBlend: alpha?.blendEnabled ?? false,
            alphaTestThreshold: (alpha?.testEnabled ?? false) ? alpha?.testThreshold : nil,
            effect: shading
        )
    }

    private func alphaProperty(at index: Int?) throws -> NIFAlphaProperty? {
        guard let index else { return nil }
        let block = try block(at: index)
        guard block.typeName == "NiAlphaProperty" else { return nil }
        return try NIFAlphaProperty(data: block.data, header: file.header)
    }
}
