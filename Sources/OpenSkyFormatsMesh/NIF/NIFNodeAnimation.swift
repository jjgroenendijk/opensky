// The node tree of a mesh with the controllers that move nodes on their own clock:
// transform keys, paths, look-at turns, and lag bones, and the bone LOD levels. A
// controller that a manager's sequence feeds is left to the sequence.
// Layout: docs/formats/nif-controllers.md.

import Foundation
import simd

nonisolated public struct NIFNodeAnimation: Sendable {
    public struct Node: Equatable, Sendable {
        public let name: String?
        /// Index into `nodes`; nil for a root.
        public let parent: Int?
        public let rest: NIFNodeTransform
    }

    public enum Motion: Equatable, Sendable {
        case keys(NIFTransformChannel)
        case path(NIFPath)
        case lookAt(NIFLookAt)
        case lag(NIFLagBone)

        /// False for keys that hold one pose, such as a skeleton's leftover export controllers.
        public var moves: Bool {
            guard case let .keys(channel) = self else { return true }
            guard let keys = channel.keys else { return false }
            let euler = keys.eulerRotations.map(\.count).max() ?? 0
            return max(keys.translations.count, keys.rotations.count, keys.scales.count, euler) > 1
        }
    }

    public struct Controller: Equatable, Sendable {
        /// Index into `nodes`.
        public let node: Int
        public let typeName: String
        /// Flag bit 3. An inactive controller leaves its node at rest.
        public let isActive: Bool
        public let timing: ControllerTiming
        public let motion: Motion

        public var isLagBone: Bool {
            if case .lag = motion {
                true
            } else {
                false
            }
        }
    }

    public let nodes: [Node]
    /// In node order, then chain order.
    public let controllers: [Controller]
    public let boneLOD: NIFBoneLODLevels?

    /// Node blocks that carry a transform and controllers.
    static let nodeTypes = NIFNode.traversedTypes.union([
        NIFSwitchNode.typeName, "NiBillboardNode", NIFCameraTrack.cameraTypeName
    ])

    public init(nodes: [Node], controllers: [Controller], boneLOD: NIFBoneLODLevels? = nil) {
        self.nodes = nodes
        self.controllers = controllers
        self.boneLOD = boneLOD
    }

    public init(file: NIFFile) throws {
        var decoder = NIFNodeAnimationDecoder(file: file)
        try decoder.readNodes()
        try decoder.readControllers()
        nodes = decoder.nodes
        controllers = decoder.controllers
        boneLOD = decoder.boneLOD()
    }

    /// Controllers that move a node when they play: active, with more than one key.
    public var playingControllers: [Controller] {
        controllers.filter { $0.isActive && $0.motion.moves }
    }
}

/// A local transform: translation, rotation, and uniform scale.
nonisolated public struct NIFNodeTransform: Equatable, Sendable {
    public var translation: SIMD3<Float>
    public var rotation: simd_quatf
    public var scale: Float

    public static let identity = Self(
        translation: .zero,
        rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        scale: 1
    )

    public init(translation: SIMD3<Float>, rotation: simd_quatf, scale: Float) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }

    /// `T * R * S`.
    public var matrix: float4x4 {
        let basis = simd_float3x3(rotation)
        return float4x4(columns: (
            SIMD4(basis.columns.0 * scale, 0), SIMD4(basis.columns.1 * scale, 0),
            SIMD4(basis.columns.2 * scale, 0), SIMD4(translation, 1)
        ))
    }

    /// `self` applied after `child`: the child's transform in this one's parent space.
    public func composed(with child: Self) -> Self {
        Self(
            translation: translation + rotation.act(child.translation * scale),
            rotation: (rotation * child.rotation).normalized,
            scale: scale * child.scale
        )
    }

    public var inverse: Self {
        let rotation = rotation.inverse
        let scale = scale != 0 ? 1 / scale : 0
        return Self(
            translation: rotation.act(-translation) * scale, rotation: rotation, scale: scale
        )
    }
}

/// `NiLookAtInterpolator`: turns its node so its look axis points at the target node.
nonisolated public struct NIFLookAt: Equatable, Sendable {
    /// Index into `NIFNodeAnimation.nodes`; nil when the target is not in the mesh.
    public let target: Int?
    public let axis: SIMD3<Float>
    public let translation: [NIFKey<SIMD3<Float>>]
    /// Radians about the look axis.
    public let roll: [NIFKey<Float>]
    public let scale: [NIFKey<Float>]

    public init(
        target: Int?, axis: SIMD3<Float>, translation: [NIFKey<SIMD3<Float>>] = [],
        roll: [NIFKey<Float>] = [], scale: [NIFKey<Float>] = []
    ) {
        self.target = target
        self.axis = axis
        self.translation = translation
        self.roll = roll
        self.scale = scale
    }
}

/// `BSLagBoneController`: how its bone trails its parent.
nonisolated public struct NIFLagBone: Equatable, Sendable {
    /// How fast the bone's position returns to rest, per second.
    public let linearVelocity: Float
    /// How fast its rotation returns to rest, per second.
    public let linearRotation: Float
    /// Units the bone may trail behind its rest position.
    public let maximumDistance: Float

    public init(linearVelocity: Float, linearRotation: Float, maximumDistance: Float) {
        self.linearVelocity = linearVelocity
        self.linearRotation = linearRotation
        self.maximumDistance = maximumDistance
    }
}
