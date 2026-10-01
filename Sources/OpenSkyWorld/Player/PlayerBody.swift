// The player's third-person body. It does not stream: the renderer holds it directly and
// it survives every scene swap (`RendererPlayerBody.swift`). The palette is pose in rig
// space, so the world placement rides the model matrix, and draw groups are rebuilt
// through `RenderScene(instances:)` when the transform changes.

import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRendering
import simd

nonisolated public final class PlayerBody {
    /// The vanilla player base record: `Skyrim.esm` `NPC_ 00000007`, editor ID
    /// `Player`. Probed rather than remembered — `openskycli actor --npc
    /// 00000007` resolves it through the same template and visual chains a
    /// streamed ACHR uses and reports a skeleton, an outfit, and a FaceGen head.
    /// A load order without that record leaves the player bodiless and says so,
    /// exactly as a missing mesh does.
    public static let baseFormID = FormID(0x0000_0007)

    /// The identity the body renders under. The player is not a plugin
    /// reference (`ReferenceKey.player`), so it carries the null FormID here and
    /// the assembly's reason-tagged skips name it as "player" in the readout.
    public static let actorFormID = FormID(0)

    public let assembly: ActorAssembly<ActorRenderAsset>
    public let animation: PlayerAnimationPlayback

    /// Where the body stands, rebuilt from the capsule every frame.
    public private(set) var transform = matrix_identity_float4x4
    /// The draw lists for the current transform.
    public private(set) var render: RenderScene

    public init(assembly: ActorAssembly<ActorRenderAsset>, animation: PlayerAnimationPlayback) {
        self.assembly = assembly
        self.animation = animation
        render = RenderScene(instances: assembly.renderPlacements(at: matrix_identity_float4x4))
    }

    /// The world transform of a body at `feetPosition` facing `yaw`. Meshes face +Y and
    /// walk-mode yaw counts from +X (docs/decisions/coordinates.md), so the rotation is
    /// `yaw - pi/2`.
    public static func transform(feetPosition: SIMD3<Float>, yaw: Float) -> float4x4 {
        MatrixMath.translation(feetPosition) * MatrixMath.rotationZ(radians: yaw - .pi / 2)
    }

    /// Moves the body. Draw groups are rebuilt only when the transform actually
    /// changed, so a standing player costs one matrix comparison per frame.
    public func place(feetPosition: SIMD3<Float>, yaw: Float) {
        let wanted = Self.transform(feetPosition: feetPosition, yaw: yaw)
        guard !Self.isEqual(wanted, transform) else { return }
        transform = wanted
        render = RenderScene(instances: assembly.renderPlacements(at: wanted))
    }

    /// GPU allocations the body keeps alive. Added to the renderer's residency
    /// set once, at attach, and never removed: unlike a cell's, they are live
    /// for the whole session.
    public var residencyAllocations: [MTLAllocation] {
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
