// The player's rendered first-person arms (issue #190).
//
// The same shape as `PlayerBody`, and deliberately so: one assembly, one
// animation, one transform rebuilt per frame, draw groups rebuilt only when
// that transform actually moved. What differs is what it is anchored to. The
// body stands on the capsule; the arms hang off the camera, so their transform
// is rebuilt from the eye pose *and* from the pose the first-person behavior
// graph just produced, because the graph is what says where the rig's camera
// bone is.
//
// The arms move every frame — including the frames a standing player does not,
// since looking around moves them — so unlike the body they rarely take the
// unchanged-transform shortcut. That is still worth keeping: a paused frame,
// or a menu-mode frame, costs one matrix comparison.

import Metal
import simd

nonisolated final class PlayerFirstPersonRig {
    let assembly: ActorAssembly<ActorRenderAsset>
    let animation: PlayerAnimationPlayback
    /// Index of `Camera1st [Cam1]` in the first-person rig, or nil when the
    /// skeleton does not declare it. Nil is a reportable fact about the
    /// install, not a crash: the arms then hang off the reference height.
    let cameraBoneIndex: Int?

    private(set) var transform = matrix_identity_float4x4
    private(set) var render: RenderScene

    init(assembly: ActorAssembly<ActorRenderAsset>, animation: PlayerAnimationPlayback) {
        self.assembly = assembly
        self.animation = animation
        cameraBoneIndex = animation.skeleton.boneNames
            .firstIndex(of: FirstPersonCamera.cameraBoneName)
        render = RenderScene(instances: assembly.renderPlacements(at: matrix_identity_float4x4))
    }

    /// The camera bone's matrix in rig space for the pose currently published,
    /// or nil when there is no pose or no such bone.
    var cameraBoneMatrix: float4x4? {
        guard
            let cameraBoneIndex,
            !animation.pose.bones.isEmpty,
            let world = try? SkeletonPoseMath.worldMatrices(
                skeleton: animation.skeleton,
                localPoses: animation.pose.bones
            ),
            cameraBoneIndex < world.count
        else { return nil }
        return world[cameraBoneIndex]
    }

    /// Hangs the arms off the eye. Draw groups are rebuilt only on a real move.
    func place(eyePosition: SIMD3<Float>, yaw: Float, pitch: Float) {
        let wanted = FirstPersonCamera.rigTransform(
            eyeMatrix: FirstPersonCamera.eyeMatrix(
                eyePosition: eyePosition, yaw: yaw, pitch: pitch
            ),
            cameraBone: cameraBoneMatrix
        )
        guard !Self.isEqual(wanted, transform) else { return }
        transform = wanted
        render = RenderScene(instances: assembly.renderPlacements(at: wanted))
    }

    /// GPU allocations the arms keep alive, added to the renderer's residency
    /// set at attach and live for the whole session, exactly as the body's are.
    var residencyAllocations: [MTLAllocation] {
        render.residencyAllocations
    }

    private static func isEqual(_ lhs: float4x4, _ rhs: float4x4) -> Bool {
        lhs.columns.0 == rhs.columns.0 && lhs.columns.1 == rhs.columns.1
            && lhs.columns.2 == rhs.columns.2 && lhs.columns.3 == rhs.columns.3
    }
}
