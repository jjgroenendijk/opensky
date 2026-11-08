// The graph-driven `RenderAnimation` for the player body. The graph steps on the 120 Hz
// simulation clock in `LocomotionBridge.plan`, because it moves the capsule; this only
// publishes that pose, so `update(at:)` ignores its time. `PlayerPoseBuffer` sits between
// the two, so a rebuilt body reattaches to the running graph.
// See docs/engine/actor-animation.md.

import OpenSkyBehavior
public import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
public import OpenSkyWorldInterface
public import simd
import Synchronization

/// Drives one set of skinned meshes from a `PlayerPoseBuffer`. The player's instance is not
/// in `RenderScene.animations`, because that list is evicted with its cell.
nonisolated public final class PlayerAnimationPlayback: RenderAnimation {
    public let skeleton: HKASkeleton
    public let pose: PlayerPoseBuffer
    private let meshes: [RenderMesh]
    private let boneIndex: SkeletonBoneIndex
    /// The revision last composed, so an unchanged pose costs one comparison.
    private let appliedRevision = Mutex<Int?>(nil)
    private let updatedBoneCount = Mutex(0)
    private let drawn = Mutex(false)
    /// Simulated bones by name, in rig space, laid over the graph's pose.
    private let ragdollBones = Mutex<[String: float4x4]>([:])
    /// Hand node to sheath node, from `ResolvedActorVisual.sheathNodes`.
    public let sheathNodes: [String: String]

    /// Bones matched into palettes by the last applied pose, for the readout.
    public var lastUpdatedBoneCount: Int {
        updatedBoneCount.withLock { $0 }
    }

    public init(
        skeleton: HKASkeleton, pose: PlayerPoseBuffer, models: [RenderModel],
        sheathNodes: [String: String] = [:]
    ) {
        self.skeleton = skeleton
        self.sheathNodes = sheathNodes
        self.pose = pose
        boneIndex = SkeletonBoneIndex(names: skeleton.boneNames)
        var seen = Set<ObjectIdentifier>()
        meshes = models.flatMap(\.meshes).filter {
            $0.isSkinned && seen.insert(ObjectIdentifier($0)).inserted
        }
    }

    /// Publishes the newest simulated pose. The time is unused: this clock is the
    /// simulation. Returns the matched bone count, so bone accounting counts the player.
    @discardableResult
    public func update(at _: Float) -> Int {
        let latest = pose.snapshot
        let isNew = appliedRevision.withLock { applied in
            defer { applied = latest.revision }
            return applied != latest.revision
        }
        guard isNew else { return lastUpdatedBoneCount }
        let count = boneCount(applying: latest.bones)
        updatedBoneCount.withLock { $0 = count }
        return count
    }

    private func boneCount(applying bones: [HKABonePose]) -> Int {
        guard let world = rigMatrices(of: bones) else { return 0 }
        let ragdoll = ragdollBones.withLock { $0 }
        let animated = SkeletonPose(bones: boneIndex, matrices: world)
        let posed = ragdoll.isEmpty
            ? animated : animated.overriding(ragdoll, parents: skeleton.parentIndices)
        let pose = WeaponSheathing.apply(sheathNodes, drawn: weaponsDrawn, to: posed)
        return meshes.reduce(0) { $0 + $1.updateSkinningPose(pose) }
    }

    private func rigMatrices(of bones: [HKABonePose]) -> [float4x4]? {
        guard !bones.isEmpty else { return nil }
        return attempt { try SkeletonPoseMath.worldMatrices(skeleton: skeleton, localPoses: bones) }
    }

    /// The graph's latest pose in rig space, one matrix per skeleton bone.
    public var animatedBoneMatrices: [float4x4]? {
        rigMatrices(of: pose.bones)
    }

    /// The graph's latest pose in rig space, by bone name.
    public var animatedBonesByName: [String: float4x4]? {
        animatedBoneMatrices.map { SkeletonPose(bones: boneIndex, matrices: $0).named }
    }

    /// Lays a ragdoll's simulated bones over the graph's pose; empty gives the pose back.
    public func setRagdollBones(_ bones: [String: float4x4]) {
        let changed = ragdollBones.withLock { old in
            defer { old = bones }
            return !(old.isEmpty && bones.isEmpty)
        }
        if changed {
            appliedRevision.withLock { $0 = nil }
        }
    }

    /// False keeps each weapon and the shield on its sheath node. A change
    /// recomposes on the next update, even without a new simulated pose.
    public var weaponsDrawn: Bool {
        get { drawn.withLock { $0 } }
        set {
            let changed = drawn.withLock { old in
                defer { old = newValue }
                return old != newValue
            }
            if changed {
                appliedRevision.withLock { $0 = nil }
            }
        }
    }

    @discardableResult
    public func resetToBindPose() -> Int {
        // Forgetting the applied revision is what makes the A/B toggle
        // reversible: turning animation back on must recompose even though the
        // simulation may not have produced a new pose in between.
        appliedRevision.withLock { $0 = nil }
        updatedBoneCount.withLock { $0 = 0 }
        return meshes.reduce(0) { $0 + $1.resetSkinningPose() }
    }
}
