// The renderer's half of the third-person player body (issue #189).
//
// The body is held here rather than in the scene because it is
// streaming-independent: `setScene` replaces every cell-owned draw list several
// times a minute, and the player is not owned by a cell. So its draw groups are
// appended to the scene's at encode time (`opaqueDrawGroups`,
// `alphaTestedDrawGroups`), which both the scene pass and the shadow pass read,
// and its GPU allocations join the residency set once and stay.
//
// See docs/engine/actor-animation.md for the clock split: the pose the body
// draws comes from the behavior graph stepped on the simulation clock, and this
// file only publishes it.

import Metal
import simd

extension Renderer {
    /// Scene opaque groups plus the player's, so one list feeds the scene pass
    /// and it cannot forget the body.
    ///
    /// The player draws last within its own list. Order between groups is a
    /// draw-call ordering only — depth testing decides what is visible — so this
    /// is about keeping the scene's grouping stable across frames rather than
    /// about correctness. The first-person arms are *not* here: they are
    /// encoded after everything else into their own depth slice
    /// (`RendererFirstPersonArms.swift`).
    public var opaqueDrawGroups: [DrawGroup] {
        guard let playerBody = frameDriver?.playerBodyRig, isPlayerBodyVisible else {
            return scene.opaque
        }
        return scene.opaque + playerBody.render.opaque
    }

    public var alphaTestedDrawGroups: [DrawGroup] {
        guard let playerBody = frameDriver?.playerBodyRig, isPlayerBodyVisible else {
            return scene.alphaTested
        }
        return scene.alphaTested + playerBody.render.alphaTested
    }

    /// What the shadow pass rasterizes: the scene plus the player's body in
    /// every mode a player exists in, whether or not the eye can see it. The
    /// reasoning is on `PlayerRigVisibility`.
    public var shadowOpaqueDrawGroups: [DrawGroup] {
        guard let playerBody = frameDriver?.playerBodyRig, rigVisibility.castsBodyShadow else {
            return scene.opaque
        }
        return scene.opaque + playerBody.render.opaque
    }

    public var shadowAlphaTestedDrawGroups: [DrawGroup] {
        guard let playerBody = frameDriver?.playerBodyRig, rigVisibility.castsBodyShadow else {
            return scene.alphaTested
        }
        return scene.alphaTested + playerBody.render.alphaTested
    }

    /// Whether the third-person body is drawn to the camera this frame.
    public var isPlayerBodyVisible: Bool {
        rigVisibility.drawsBody
    }

    /// Grows the draw and instance rings to cover the scene plus the body. The
    /// scene's own sizing runs in `setScene` and knows nothing about the player,
    /// so a body attached over a large scene has to ask for its own headroom.
    public func growRingsForPlayerBody(_ body: any RenderRig) throws {
        try growRings(
            drawCount: scene.drawCount + body.render.drawCount,
            instanceCount: scene.instanceCount + body.render.instanceCount
        )
    }
}
