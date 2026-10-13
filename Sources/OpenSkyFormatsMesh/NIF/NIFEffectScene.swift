// A NIF kept as a node tree with unlit shapes, for meshes that sequences animate
// node by node, such as the perk sky. The static model path flattens the tree and
// drops additive shapes, so it cannot play these. See docs/formats/nif-sequences.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct NIFEffectScene: Sendable {
    public struct Node: Sendable {
        public let name: String?
        /// Index into `nodes`; nil for a root.
        public let parent: Int?
        public let translation: SIMD3<Float>
        public let rotation: simd_quatf
        public let scale: Float
        public let isHidden: Bool
        /// nif.xml `BillboardMode` of an `NiBillboardNode`.
        public let billboardMode: UInt16?
    }

    public struct Shape: Sendable {
        /// The shape's own node in `nodes`.
        public let node: Int
        public let positions: [SIMD3<Float>]
        /// Zero where the shape stores none; the falloff then stays at its start.
        public let normals: [SIMD3<Float>]
        public let uvs: [SIMD2<Float>]
        public let colors: [SIMD4<Float>]
        public let indices: [UInt16]
        public let material: NIFEffectMaterial
        /// The shader property block, which sequence colour and alpha tracks name.
        public let shaderBlock: Int?
    }

    public let nodes: [Node]
    /// In draw order: a `BSOrderedNode` draws its children in this order.
    public let shapes: [Shape]

    /// The first node with this name, compared without case.
    public func node(named name: String) -> Int? {
        nodes.firstIndex { $0.name?.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The node's transform in the mesh, with `local` replacing the stored ones.
    public func modelTransform(of index: Int, local: (Int) -> float4x4) -> float4x4 {
        var transform = local(index)
        var parent = nodes[index].parent
        var depth = 0
        while let current = parent, depth < Self.maxDepth {
            transform = local(current) * transform
            parent = nodes[current].parent
            depth += 1
        }
        return transform
    }

    /// The stored transform `T * R * S`.
    public func restTransform(of index: Int) -> float4x4 {
        let node = nodes[index]
        return Self.transform(node.translation, node.rotation, node.scale)
    }

    public static func transform(
        _ translation: SIMD3<Float>, _ rotation: simd_quatf, _ scale: Float
    ) -> float4x4 {
        let basis = simd_float3x3(rotation)
        return float4x4(columns: (
            SIMD4(basis.columns.0 * scale, 0), SIMD4(basis.columns.1 * scale, 0),
            SIMD4(basis.columns.2 * scale, 0), SIMD4(translation, 1)
        ))
    }

    static let maxDepth = 64
    static let billboardType = "NiBillboardNode"

    public init(file: NIFFile) throws {
        var builder = NIFEffectSceneBuilder(file: file)
        for root in file.roots {
            try builder.walk(from: root)
        }
        nodes = builder.nodes
        shapes = builder.shapes
    }
}

/// nif.xml `AlphaFunction` factors: 0 one, 1 zero, 6 source alpha, 7 one minus
/// source alpha, and others.
nonisolated public struct NIFBlend: Hashable, Sendable {
    public let source: UInt16
    public let destination: UInt16

    public init(source: UInt16, destination: UInt16) {
        self.source = source
        self.destination = destination
    }
}

/// The unlit look of one shape: an effect shader's, or a lit shader's diffuse.
nonisolated public struct NIFEffectMaterial: Hashable, Sendable {
    public var sourceTexture: String?
    public var shading = EffectShading(
        baseColor: [1, 1, 1, 1], baseColorScale: 1, paletteTexture: nil, paletteColor: false,
        paletteAlpha: false, falloff: nil, vertexColors: false, vertexAlpha: false
    )
    public var uvOffset: SIMD2<Float> = [0, 0]
    public var uvScale: SIMD2<Float> = [1, 1]
    /// Nil draws opaque.
    public var blend: NIFBlend?
    public var alphaTest: Float?

    public init() {}
}
