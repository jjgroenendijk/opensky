// Lag bones of a creature skeleton: `BSLagBoneController` nodes outside the Havok rig.
// Each trails its rest under the rig bone above it, as the game's lag rule moves it
// (docs/formats/nif-controllers.md#node-controller-rules).

import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import simd

nonisolated public struct ActorLagBoneRig: Sendable {
    public struct Bone: Equatable, Sendable {
        public let name: String
        /// The rig bone the lag bone hangs from.
        public let parent: String
        /// The lag bone's rest in the parent's space.
        public let rest: NIFNodeTransform
        public let lag: NIFLagBone
    }

    public let bones: [Bone]

    /// The lag bones of `file` that hang from a bone of `rig`, nil when there are none.
    public init?(file: NIFFile, rigBones: Set<String>) {
        guard let animation = try? NIFNodeAnimation(file: file) else { return nil }
        var bones: [Bone] = []
        for controller in animation.controllers {
            guard
                case let .lag(lag) = controller.motion,
                let name = animation.nodes[controller.node].name, !rigBones.contains(name),
                let anchor = Self.anchor(of: controller.node, in: animation, rigBones: rigBones)
            else { continue }
            bones.append(Bone(name: name, parent: anchor.name, rest: anchor.rest, lag: lag))
        }
        guard !bones.isEmpty else { return nil }
        self.bones = bones
    }

    public init(bones: [Bone]) {
        self.bones = bones
    }

    /// The nearest rig bone above `node`, with `node`'s rest composed into its space.
    private static func anchor(
        of node: Int, in animation: NIFNodeAnimation, rigBones: Set<String>
    ) -> (name: String, rest: NIFNodeTransform)? {
        var rest = animation.nodes[node].rest
        var current = animation.nodes[node].parent
        var depth = 0
        while let index = current, depth < 64 {
            let parent = animation.nodes[index]
            if let name = parent.name, rigBones.contains(name) {
                return (name, rest)
            }
            rest = parent.rest.composed(with: rest)
            current = parent.parent
            depth += 1
        }
        return nil
    }
}

/// Where each lag bone of one actor was last frame, in the world.
nonisolated public struct ActorLagBoneState: Sendable {
    public private(set) var world: [String: NIFNodeTransform] = [:]
    /// How far each lag bone trails its rest, in world units.
    public private(set) var offsets: [String: Float] = [:]

    public init() {}

    /// `pose` with the lag bones added after its rig bones, stepped `deltaTime` toward
    /// their rests while the actor stands at `placement`.
    public mutating func pose(
        _ pose: SkeletonPose, rig: ActorLagBoneRig, index: SkeletonBoneIndex,
        placement: float4x4, deltaTime: Float
    ) -> SkeletonPose {
        var matrices = pose.matrices
        let toActor = placement.inverse
        for bone in rig.bones {
            guard
                let parentIndex = pose.bones.index(of: bone.parent),
                parentIndex < pose.matrices.count
            else { continue }
            let parent = NIFNodeTransform(matrix: placement * pose.matrices[parentIndex])
            let goal = parent.composed(with: bone.rest)
            let current = NIFLagBoneMotion.step(
                world[bone.name] ?? goal, toward: goal, bone.lag, deltaTime: deltaTime
            )
            world[bone.name] = current
            offsets[bone.name] = simd_distance(current.translation, goal.translation)
            matrices.append(toActor * current.matrix)
        }
        return SkeletonPose(bones: index, matrices: matrices)
    }
}

nonisolated extension NIFNodeTransform {
    /// The transform of a matrix with a uniform scale.
    init(matrix: float4x4) {
        let column0 = SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        let column1 = SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)
        let column2 = SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        let scale = simd_length(column0)
        let unit = scale > 0 ? 1 / scale : 1
        let rotation = simd_quatf(simd_float3x3(column0 * unit, column1 * unit, column2 * unit))
        self.init(
            translation: SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z),
            rotation: rotation.normalized, scale: scale
        )
    }
}
