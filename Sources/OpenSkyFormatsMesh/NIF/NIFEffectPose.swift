// The state of an effect scene while sequences play: each node's transform and
// visibility, and each shape's material after colour and alpha tracks.
// Effect shader variables: docs/formats/nif-sequences.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct NIFEffectPose: Sendable {
    /// One sequence and the seconds since it started.
    public struct Playing: Sendable {
        public let sequence: NIFSequence
        public let seconds: Float

        public init(_ sequence: NIFSequence, seconds: Float) {
            self.sequence = sequence
            self.seconds = seconds
        }
    }

    /// One shape ready to draw.
    public struct ShapeState: Sendable {
        public let shape: Int
        /// Shape to mesh space.
        public let transform: float4x4
        public let material: NIFEffectMaterial
        public let isVisible: Bool
        /// The nearest billboard node above the shape, if any.
        public let billboard: Billboard?
    }

    /// A billboard node turns to the camera, so the shape's transform splits there.
    public struct Billboard: Sendable {
        public let mode: UInt16
        /// Billboard node to mesh space.
        public let node: float4x4
        /// Shape to billboard node space.
        public let below: float4x4
    }

    public private(set) var locals: [float4x4]
    public private(set) var hidden: [Bool]
    private var floats: [Int: [UInt32: Float]] = [:]
    private var colors: [Int: [UInt32: SIMD3<Float>]] = [:]
    /// Alpha test thresholds by node, 0 to 1.
    private var alphaTests: [Int: Float] = [:]
    /// A `NiFloatExtraData` named with this prefix shows or hides the node it names.
    public static let visibilityExtraDataPrefix = "hkVis:"

    /// Later sequences in `playing` win where two animate the same value.
    public init(scene: NIFEffectScene, playing: [Playing]) {
        locals = scene.nodes.indices.map(scene.restTransform)
        hidden = scene.nodes.map(\.isHidden)
        for item in playing {
            let time = item.sequence.keyTime(after: item.seconds)
            for track in item.sequence.tracks {
                apply(track, at: time, scene: scene)
            }
        }
    }

    private mutating func apply(_ track: NIFSequenceTrack, at time: Float, scene: NIFEffectScene) {
        switch (track.target, track.channel) {
        case let (.node(name), .transform(channel)):
            guard let index = scene.node(named: name) else { return }
            let node = scene.nodes[index]
            locals[index] = NIFEffectScene.transform(
                channel.translation(at: time) ?? node.translation,
                channel.rotation(at: time) ?? node.rotation,
                channel.scale(at: time) ?? node.scale
            )
        case let (.node(name), .visibility(keys)):
            guard let index = scene.node(named: name), let on = NIFKeySampler.step(keys, at: time)
            else { return }
            hidden[index] = !on
        case (_, .alphaTestReference), (_, .extraDataFloat):
            applyAlphaOrVisibility(track, at: time, scene: scene)
        case let (target, .shaderFloat(variable, keys)):
            guard let value = NIFKeySampler.float(keys, at: time) else { return }
            for block in Self.shaderBlocks(target, scene: scene) {
                floats[block, default: [:]][variable] = value
            }
        case let (target, .shaderColor(variable, keys)):
            guard let value = NIFKeySampler.vector(keys, at: time) else { return }
            for block in Self.shaderBlocks(target, scene: scene) {
                colors[block, default: [:]][variable] = value
            }
        default:
            return
        }
    }

    /// An alpha test threshold track, or a float extra data track that names a
    /// node to show or hide.
    private mutating func applyAlphaOrVisibility(
        _ track: NIFSequenceTrack, at time: Float, scene: NIFEffectScene
    ) {
        switch (track.target, track.channel) {
        case let (.node(name), .alphaTestReference(keys)):
            guard
                let index = scene.node(named: name), let value = NIFKeySampler.float(
                    keys,
                    at: time
                )
            else { return }
            alphaTests[index] = simd_clamp(value / 255, 0, 1)
        case let (_, .extraDataFloat(name, keys)):
            guard
                name.hasPrefix(Self.visibilityExtraDataPrefix),
                let index = scene
                    .node(named: String(name.dropFirst(Self.visibilityExtraDataPrefix.count))),
                let value = NIFKeySampler.float(keys, at: time)
            else { return }
            hidden[index] = value < 0.5
        default:
            return
        }
    }

    /// A shader target names its block, or a shape whose block it means.
    private static func shaderBlocks(
        _ target: NIFSequenceTrack.Target, scene: NIFEffectScene
    ) -> [Int] {
        switch target {
        case let .shaderProperty(block): return [block]
        case let .node(name):
            guard let node = scene.node(named: name) else { return [] }
            return scene.shapes.filter { $0.node == node }.compactMap(\.shaderBlock)
        }
    }

    public func shapes(of scene: NIFEffectScene) -> [ShapeState] {
        scene.shapes.indices.map { index in
            let shape = scene.shapes[index]
            return ShapeState(
                shape: index,
                transform: scene.modelTransform(of: shape.node) { locals[$0] },
                material: material(shape),
                isVisible: isVisible(shape.node, scene: scene),
                billboard: billboard(above: shape.node, scene: scene)
            )
        }
    }

    private func isVisible(_ node: Int, scene: NIFEffectScene) -> Bool {
        var current: Int? = node
        while let index = current {
            if hidden[index] {
                return false
            }
            current = scene.nodes[index].parent
        }
        return true
    }

    private func billboard(above node: Int, scene: NIFEffectScene) -> Billboard? {
        var below = matrix_identity_float4x4
        var current: Int? = node
        while let index = current {
            if let mode = scene.nodes[index].billboardMode {
                let placed = scene.modelTransform(of: index) { locals[$0] }
                return Billboard(mode: mode, node: placed, below: below)
            }
            below = locals[index] * below
            current = scene.nodes[index].parent
        }
        return nil
    }

    /// nif.xml `EffectShaderControlledVariable`: 0 emissive multiple, 1 to 4 the
    /// falloff, 5 alpha, 6 to 9 the UV offset and scale. Colour 0 is the emissive colour.
    private func material(_ shape: NIFEffectScene.Shape) -> NIFEffectMaterial {
        var material = shape.material
        if let threshold = alphaTests[shape.node], material.alphaTest != nil {
            material.alphaTest = threshold
        }
        guard let block = shape.shaderBlock else { return material }
        for (variable, value) in floats[block] ?? [:] {
            switch variable {
            case 0: material.shading.baseColorScale = value
            case 1 ... 4:
                var falloff = material.shading.falloff ?? [1, 0, 1, 1]
                falloff[Int(variable) - 1] = value
                material.shading.falloff = falloff
            case 5: material.shading.baseColor.w = value
            case 6: material.uvOffset.x = value
            case 7: material.uvScale.x = value
            case 8: material.uvOffset.y = value
            case 9: material.uvScale.y = value
            default: break
            }
        }
        if let emissive = colors[block]?[0] {
            material.shading.baseColor = SIMD4(emissive, material.shading.baseColor.w)
        }
        return material
    }
}
