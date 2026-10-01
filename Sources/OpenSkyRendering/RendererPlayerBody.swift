// The renderer's half of the third-person body. No cell owns the player, so its draw
// groups join the scene's at encode time and its GPU allocations stay resident.
// The pose comes from the behavior graph on the simulation clock
// (docs/engine/actor-animation.md).

import Metal
import simd

extension Renderer {
    /// Scene opaque groups plus the player's, so the scene pass cannot forget the body.
    /// Order is for stable grouping only; depth decides visibility. The first-person arms
    /// are drawn separately (`RendererFirstPersonArms.swift`).
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
