// The graph-driven `RenderAnimation` (issue #189): the conformer that turns the
// behavior graph's per-step pose into the player body's bone palettes.
//
// Two clocks meet here and it matters which one wins. The behavior graph is
// stepped by `LocomotionBridge.plan` on the *simulation* clock — the fixed 120
// Hz substeps `Renderer.advanceCamera` drives — because the graph is part of
// movement: it consumes the same `Speed` and `Direction` the capsule moves by,
// and a graph advanced on a second clock could report a state the capsule was
// never in. The renderer's wall-clock animation pass
// (`Renderer.updateAnimations(deltaTime:)`) therefore does not advance this
// animation at all. It only *publishes* the pose the simulation already
// produced, so `update(at:)` ignores its time argument. NPCs keep the wall-clock
// single-clip path from M6 unchanged; graph-driven NPC locomotion is M16 AI
// (docs/engine/actor-animation.md).
//
// The pose crosses between the two through `PlayerPoseBuffer`, a plain box both
// sides hold. Neither owns the other, so there is no cycle between the bridge
// and the render side, and a body that is rebuilt (a new appearance, a new
// equipped set) reattaches to the same running graph.

import simd

/// The latest pose the behavior graph produced, published by the locomotion
/// bridge and consumed by the render side.
///
/// `revision` is what makes the consumer cheap: an unchanged revision means the
/// simulation ran no step since the last frame — a paused frame, or a frame
/// shorter than one fixed step — and the palettes already hold the right
/// matrices, so the whole compose-and-upload path is skipped rather than redone.
nonisolated final class PlayerPoseBuffer {
    private(set) var bones: [HKABonePose] = []
    private(set) var revision = 0

    func publish(_ bones: [HKABonePose]) {
        self.bones = bones
        revision &+= 1
    }

    /// Drops the pose, so a body attached after a reset composes from the
    /// reference pose rather than from wherever the player last stood.
    func clear() {
        bones = []
        revision &+= 1
    }
}

/// Drives one set of skinned meshes from a `PlayerPoseBuffer`.
///
/// This is a `RenderAnimation` like `ActorAnimationPlayback`, so it can join
/// `RenderScene.animations` unchanged if a future caller wants it there. The
/// player's own instance does not: the body is streaming-independent and the
/// renderer holds it directly (`RendererPlayerBody.swift`), because everything
/// in `RenderScene.animations` is evicted with its owning cell.
nonisolated final class PlayerAnimationPlayback: RenderAnimation {
    let skeleton: HKASkeleton
    let pose: PlayerPoseBuffer
    private let meshes: [RenderMesh]
    /// The revision last composed, so an unchanged pose costs one comparison.
    private var appliedRevision: Int?
    /// Bones matched into palettes by the last applied pose, for the readout.
    private(set) var lastUpdatedBoneCount = 0

    init(skeleton: HKASkeleton, pose: PlayerPoseBuffer, models: [RenderModel]) {
        self.skeleton = skeleton
        self.pose = pose
        var seen = Set<ObjectIdentifier>()
        meshes = models.flatMap(\.meshes).filter {
            $0.isSkinned && seen.insert(ObjectIdentifier($0)).inserted
        }
    }

    /// Publishes the newest simulated pose into the palettes.
    ///
    /// The time argument is deliberately unused: this animation's clock is the
    /// simulation, not the wall clock (see the file comment). Returning the
    /// matched bone count keeps the `RenderAnimation` contract, so the
    /// renderer's per-frame bone accounting counts the player exactly as it
    /// counts an NPC.
    @discardableResult
    func update(at _: Float) -> Int {
        guard appliedRevision != pose.revision else { return lastUpdatedBoneCount }
        appliedRevision = pose.revision
        guard !pose.bones.isEmpty else {
            lastUpdatedBoneCount = 0
            return 0
        }
        guard
            let world = try? SkeletonPoseMath.worldMatrices(
                skeleton: skeleton,
                localPoses: pose.bones
            )
        else {
            lastUpdatedBoneCount = 0
            return 0
        }
        var named: [String: float4x4] = [:]
        for (name, transform) in zip(skeleton.boneNames, world) where named[name] == nil {
            named[name] = transform
        }
        lastUpdatedBoneCount = meshes.reduce(0) { $0 + $1.updateSkinningPose(named) }
        return lastUpdatedBoneCount
    }

    @discardableResult
    func resetToBindPose() -> Int {
        // Forgetting the applied revision is what makes the A/B toggle
        // reversible: turning animation back on must recompose even though the
        // simulation may not have produced a new pose in between.
        appliedRevision = nil
        lastUpdatedBoneCount = 0
        return meshes.reduce(0) { $0 + $1.resetSkinningPose() }
    }
}
