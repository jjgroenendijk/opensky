// The player's rendered third-person body (issue #189).
//
// Two facts shape this type.
//
// The body is streaming-independent. Everything a cell build produces —
// placements, animations, residency — is evicted when that cell is evicted, and
// the player is never in one cell in that sense: it is the thing the cells move
// around. So the body is not a `CellScene` product and not a member of
// `RenderScene.animations`. The renderer holds it directly and it survives every
// scene swap (`RendererPlayerBody.swift`).
//
// The body moves every frame, and skinned geometry is placed twice: once by the
// draw's model matrix and once by the bone palette. The palette is
// pose-in-rig-space (`RenderMesh.updateSkinningPose`), so the world placement
// has to ride the model matrix, which means the draw groups are rebuilt when
// the transform changes rather than baked once. That rebuild is group
// accumulation over the handful of meshes one actor carries — no allocation, no
// upload — and it runs through `RenderScene(instances:)` so the player is
// grouped by exactly the rule every other placement is grouped by.

import Metal
import simd

nonisolated final class PlayerBody {
    /// The vanilla player base record: `Skyrim.esm` `NPC_ 00000007`, editor ID
    /// `Player`. Probed rather than remembered — `openskycli actor --npc
    /// 00000007` resolves it through the same template and visual chains a
    /// streamed ACHR uses and reports a skeleton, an outfit, and a FaceGen head.
    /// A load order without that record leaves the player bodiless and says so,
    /// exactly as a missing mesh does.
    static let baseFormID = FormID(0x0000_0007)

    /// The identity the body renders under. The player is not a plugin
    /// reference (`ReferenceKey.player`), so it carries the null FormID here and
    /// the assembly's reason-tagged skips name it as "player" in the readout.
    static let actorFormID = FormID(0)

    let assembly: ActorAssembly<ActorRenderAsset>
    let animation: PlayerAnimationPlayback

    /// Where the body stands, rebuilt from the capsule every frame.
    private(set) var transform = matrix_identity_float4x4
    /// The draw lists for the current transform.
    private(set) var render: RenderScene

    init(assembly: ActorAssembly<ActorRenderAsset>, animation: PlayerAnimationPlayback) {
        self.assembly = assembly
        self.animation = animation
        render = RenderScene(instances: assembly.renderPlacements(at: matrix_identity_float4x4))
    }

    /// The world transform of a body standing at `feetPosition` and facing
    /// `yaw`.
    ///
    /// The quarter turn is the actor convention, not a fudge. A Skyrim ACHR's
    /// `angleZ` is measured clockwise from north, and `MatrixMath.placement`
    /// applies it as `rotationZ(-angleZ)`, so an actor placed at `angleZ` 0
    /// stands unrotated and faces +Y — the character meshes are authored facing
    /// +Y. Walk-mode yaw is measured the other way, counterclockwise from +X
    /// (`docs/decisions/coordinates.md`), so turning the mesh's +Y onto the
    /// camera's `(cos yaw, sin yaw)` is a rotation of `yaw - pi/2`.
    static func transform(feetPosition: SIMD3<Float>, yaw: Float) -> float4x4 {
        MatrixMath.translation(feetPosition) * MatrixMath.rotationZ(radians: yaw - .pi / 2)
    }

    /// Moves the body. Draw groups are rebuilt only when the transform actually
    /// changed, so a standing player costs one matrix comparison per frame.
    func place(feetPosition: SIMD3<Float>, yaw: Float) {
        let wanted = Self.transform(feetPosition: feetPosition, yaw: yaw)
        guard !Self.isEqual(wanted, transform) else { return }
        transform = wanted
        render = RenderScene(instances: assembly.renderPlacements(at: wanted))
    }

    /// GPU allocations the body keeps alive. Added to the renderer's residency
    /// set once, at attach, and never removed: unlike a cell's, they are live
    /// for the whole session.
    var residencyAllocations: [MTLAllocation] {
        render.residencyAllocations
    }

    /// Exact equality is what is wanted here: the transform is rebuilt from the
    /// same two inputs every frame, so bitwise-identical means "nothing moved"
    /// and anything else is a real move, however small.
    private static func isEqual(_ lhs: float4x4, _ rhs: float4x4) -> Bool {
        lhs.columns.0 == rhs.columns.0 && lhs.columns.1 == rhs.columns.1
            && lhs.columns.2 == rhs.columns.2 && lhs.columns.3 == rhs.columns.3
    }
}
