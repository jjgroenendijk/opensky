// Animation-safe equipment swap (issue #178, roadmap item 12.2.1).
//
// The chosen behaviour, stated once here and asserted below: a mid-clip swap
// **resumes**, it does not restart. Nothing in the swap path holds a clip
// phase. `Renderer.animationTime` is a renderer-owned monotonic clock that a
// cell rebuild never touches, and `RenderScene.updateAnimations(at:)` samples
// every resident actor from it, so the playback object a rebuild produces is
// sampled at the same world time as the one it replaced. A restart would need
// something to store a per-actor start time, and deliberately nothing does.
// The tests below pin the observable consequence: the same pose applied to two
// independently built model sets produces identical palettes.
//
// The second half of the requirement is that no bind-pose frame appears. A
// fresh `RenderMesh` starts on its bind palette, so the guarantee is one of
// ordering rather than of state: `Renderer.draw` calls
// `updateAnimationsFromWallClock()` before it encodes, so the first frame that
// can show a rebuilt actor has already posed it. What is asserted here is the
// precondition that makes that work for equipment — an attachment is a skinned
// mesh, so `ActorAnimationPlayback` collects it alongside the body meshes and
// poses it in the same pass rather than leaving it behind at bind pose.
//
// Synthetic meshes and a synthetic pose. Frame-level animation proof is
// `ActorAnimationRenderTests`; this suite is about what a swap does to the
// palettes.

import Metal
@testable import opensky
import simd
import Testing

struct ActorEquipmentSwapTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private static var hasDevice: Bool {
        device != nil
    }

    private static let spine = "NPC Spine [Spn0]"

    /// A single-triangle rigid model, which is what a weapon NIF flattens to
    /// before `RigidAttachment` binds it to a bone.
    private func rigidModel(name: String) -> Model {
        Model(
            meshes: [Mesh(
                name: name,
                transform: matrix_identity_float4x4,
                positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
                normals: [SIMD3(0, 0, 1), SIMD3(0, 0, 1), SIMD3(0, 0, 1)],
                tangents: [],
                bitangents: [],
                uvs: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1)],
                colors: [],
                indices: [0, 1, 2],
                materialSlot: 0
            )],
            // No materials: these tests build `RenderMesh` directly and never
            // resolve a material slot.
            materials: [],
            skippedShapeCount: 0
        )
    }

    private func renderMesh(
        _ name: String,
        bone: String,
        device: MTLDevice
    ) throws -> RenderMesh {
        let bound = RigidAttachment.skinned(
            rigidModel(name: name), to: bone, restTransform: matrix_identity_float4x4
        )
        return try RenderMesh(device: device, mesh: bound.meshes[0])
    }

    private func pose(hand: SIMD3<Float>) -> [String: float4x4] {
        [
            Self.spine: matrix_identity_float4x4,
            ActorAttachmentBone.drawnWeapon: MatrixMath.translation(hand)
        ]
    }

    // MARK: - The attachment rides the actor's pose pass

    /// `ActorAnimationPlayback` collects `models.flatMap(\.meshes)` filtered on
    /// `isSkinned`, so an attachment is only posed each frame if it reports as
    /// skinned. It does, which is the whole reason `RigidAttachment` exists.
    @Test(.enabled(if: Self.hasDevice))
    func attachmentIsASkinnedMeshSoPlaybackCollectsIt() throws {
        let device = try #require(Self.device)
        let weapon = try renderMesh(
            "sword", bone: ActorAttachmentBone.drawnWeapon, device: device
        )

        #expect(weapon.isSkinned)
        // An unbound rigid model is not skinned, so the difference is the bind.
        let loose = try RenderMesh(device: device, mesh: rigidModel(name: "sword").meshes[0])
        #expect(!loose.isSkinned)
    }

    @Test(.enabled(if: Self.hasDevice))
    func onePoseMovesBodyAndAttachmentTogether() throws {
        let device = try #require(Self.device)
        let body = try renderMesh("body", bone: Self.spine, device: device)
        let weapon = try renderMesh(
            "sword", bone: ActorAttachmentBone.drawnWeapon, device: device
        )
        let sample = pose(hand: SIMD3(0, 50, 0))

        #expect(body.updateSkinningPose(sample) == 1)
        #expect(weapon.updateSkinningPose(sample) == 1)

        #expect(weapon.currentBoneMatrices.first?.columns.3 == SIMD4(0, 50, 0, 1))
        #expect(body.currentBoneMatrices.first?.columns.3 == SIMD4(0, 0, 0, 1))
    }

    /// A pose that names no attachment bone leaves the weapon on its bind
    /// palette rather than collapsing it to the origin — the same
    /// unmatched-bone rule the body meshes already rely on.
    @Test(.enabled(if: Self.hasDevice))
    func poseWithoutTheAttachmentBoneLeavesTheBindPalette() throws {
        let device = try #require(Self.device)
        let weapon = try renderMesh(
            "sword", bone: ActorAttachmentBone.drawnWeapon, device: device
        )
        let bind = weapon.currentBoneMatrices

        #expect(weapon.updateSkinningPose([Self.spine: MatrixMath.translation(SIMD3(9, 9, 9))])
            == 0)

        #expect(weapon.currentBoneMatrices.first?.columns.3 == bind.first?.columns.3)
    }

    // MARK: - Resume, not restart

    /// Two independently built model sets — what a rebuild produces — posed at
    /// the same world time land on identical palettes. That is what "resume"
    /// means here: the swap carries no phase of its own, so the shared clock
    /// alone decides the pose.
    @Test(.enabled(if: Self.hasDevice))
    func swapResumesAtTheSharedClockRatherThanRestarting() throws {
        let device = try #require(Self.device)
        let before = try renderMesh(
            "sword", bone: ActorAttachmentBone.drawnWeapon, device: device
        )
        let after = try renderMesh(
            "sword", bone: ActorAttachmentBone.drawnWeapon, device: device
        )
        let sample = pose(hand: SIMD3(3, 4, 5))

        // The pre-swap object has been running; the post-swap one is fresh.
        before.updateSkinningPose(pose(hand: SIMD3(1, 1, 1)))
        before.updateSkinningPose(sample)
        after.updateSkinningPose(sample)

        #expect(before.currentBoneMatrices.count == after.currentBoneMatrices.count)
        for index in before.currentBoneMatrices.indices {
            #expect(simd_distance(
                before.currentBoneMatrices[index].columns.3,
                after.currentBoneMatrices[index].columns.3
            ) < 1e-6)
        }
    }

    /// Turning animation off restores the bind palette for an attachment too,
    /// so the A/B toggle keeps meaning the same thing on an armed actor.
    @Test(.enabled(if: Self.hasDevice))
    func attachmentResetsToItsBindPalette() throws {
        let device = try #require(Self.device)
        let weapon = try renderMesh(
            "sword", bone: ActorAttachmentBone.drawnWeapon, device: device
        )
        let bind = weapon.currentBoneMatrices
        weapon.updateSkinningPose(pose(hand: SIMD3(7, 7, 7)))

        #expect(weapon.resetSkinningPose() == 1)
        #expect(weapon.currentBoneMatrices.first?.columns.3 == bind.first?.columns.3)
    }
}
