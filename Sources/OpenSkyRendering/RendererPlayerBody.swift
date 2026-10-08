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
        let body = isPlayerBodyVisible ? frameDriver?.playerBodyRig?.render.opaque : nil
        return Self.joined(
            scene.opaque, body ?? [], effects.scene.opaque, effects.loadingCover?.opaque ?? []
        )
    }

    public var alphaTestedDrawGroups: [DrawGroup] {
        let body = isPlayerBodyVisible ? frameDriver?.playerBodyRig?.render.alphaTested : nil
        return Self.joined(
            scene.alphaTested, body ?? [], effects.scene.alphaTested,
            effects.loadingCover?.alphaTested ?? []
        )
    }

    /// What the shadow pass rasterizes: the scene plus the player's body in
    /// every mode a player exists in, whether or not the eye can see it. The
    /// reasoning is on `PlayerRigVisibility`.
    public var shadowOpaqueDrawGroups: [DrawGroup] {
        let body = rigVisibility.castsBodyShadow ? frameDriver?.playerBodyRig?.render.opaque : nil
        return Self.joined(scene.opaque, body ?? [])
    }

    public var shadowAlphaTestedDrawGroups: [DrawGroup] {
        let body = rigVisibility.castsBodyShadow
            ? frameDriver?.playerBodyRig?.render.alphaTested : nil
        return Self.joined(scene.alphaTested, body ?? [])
    }

    /// Joins the lists once per frame, before the first pass reads them. The shadow
    /// pass reads them once per cascade, so joining on each read copied the scene lists.
    func refreshFrameDrawGroups() {
        frameDrawGroups = FrameDrawGroups(
            opaque: opaqueDrawGroups,
            alphaTested: alphaTestedDrawGroups,
            shadowOpaque: shadowOpaqueDrawGroups,
            shadowAlphaTested: shadowAlphaTestedDrawGroups
        )
    }

    /// The scene list shares its storage when nothing joins it.
    private static func joined(_ base: [DrawGroup], _ extras: [DrawGroup]...) -> [DrawGroup] {
        guard extras.contains(where: { !$0.isEmpty }) else { return base }
        var result = base
        result.reserveCapacity(base.count + extras.reduce(0) { $0 + $1.count })
        for extra in extras {
            result += extra
        }
        return result
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
            drawCount: scene.drawCount + body.render.drawCount + effects.scene.drawCount,
            instanceCount: scene.instanceCount + body.render.instanceCount
                + effects.scene.instanceCount
        )
    }
}

/// The draw-group lists of one frame, as `refreshFrameDrawGroups()` joined them.
struct FrameDrawGroups {
    var opaque: [DrawGroup] = []
    var alphaTested: [DrawGroup] = []
    var shadowOpaque: [DrawGroup] = []
    var shadowAlphaTested: [DrawGroup] = []
}
