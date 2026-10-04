// The graph-driven `RenderAnimation` for the player body. The graph steps on the 120 Hz
// simulation clock in `LocomotionBridge.plan`, because it moves the capsule; this only
// publishes that pose, so `update(at:)` ignores its time. `PlayerPoseBuffer` sits between
// the two, so a rebuilt body reattaches to the running graph.
// See docs/engine/actor-animation.md.

import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyRendering
import simd
import Synchronization

/// The latest pose the behavior graph produced. An unchanged `revision` means no step ran
/// since the last frame, so the consumer skips the compose-and-upload path.
nonisolated public final class PlayerPoseBuffer: Sendable {
    nonisolated public struct Snapshot: Sendable {
        public var bones: [HKABonePose] = []
        public var revision = 0
    }

    private let state = Mutex(Snapshot())

    public init() {}

    public var snapshot: Snapshot {
        state.withLock { $0 }
    }

    public var bones: [HKABonePose] {
        state.withLock { $0.bones }
    }

    public var revision: Int {
        state.withLock { $0.revision }
    }

    public func publish(_ bones: [HKABonePose]) {
        state.withLock {
            $0.bones = bones
            $0.revision &+= 1
        }
    }

    /// Drops the pose, so a body attached after a reset composes from the
    /// reference pose rather than from wherever the player last stood.
    public func clear() {
        state.withLock {
            $0.bones = []
            $0.revision &+= 1
        }
    }
}

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

    /// Bones matched into palettes by the last applied pose, for the readout.
    public var lastUpdatedBoneCount: Int {
        updatedBoneCount.withLock { $0 }
    }

    public init(skeleton: HKASkeleton, pose: PlayerPoseBuffer, models: [RenderModel]) {
        self.skeleton = skeleton
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
        guard
            !bones.isEmpty,
            let world = try? SkeletonPoseMath.worldMatrices(skeleton: skeleton, localPoses: bones)
        else { return 0 }
        let pose = SkeletonPose(bones: boneIndex, matrices: world)
        return meshes.reduce(0) { $0 + $1.updateSkinningPose(pose) }
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
