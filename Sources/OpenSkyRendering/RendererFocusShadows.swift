// Focus shadows: the actors nearest the camera each get a small sun-shadow map in the
// auxiliary array. Only actors draw into them; the shader takes the darker of the
// cascades and the focus map (docs/rendering/shadows.md).

import OpenSkyFormatsCore
import OpenSkyRenderCore
import OpenSkyShaderTypes
import simd

/// The focus views one frame drew.
struct FocusShadowFrame {
    var views: [float4x4] = []
    /// The largest bias any view needs, in depth units.
    var bias: Float = 0

    /// One of the frame uniforms' four matrices; identity pads the unused ones.
    func view(_ index: Int) -> float4x4 {
        index < views.count ? views[index] : matrix_identity_float4x4
    }
}

extension Renderer {
    /// One view per focused actor, in slices 0 up to `ShadowConstantFocusCount`.
    func focusViews() -> [AuxiliaryShadowView] {
        let count = min(max(focusShadowCount, 0), ShadowConstant.focusCount.rawValue)
        guard count > 0 else { return [] }
        let targets = FocusShadowMath.pick(
            focusShadowTargets(), viewer: frameInput.view.position, count: count
        )
        var frame = FocusShadowFrame()
        let views = targets.enumerated().map { slice, target in
            let matrix = FocusShadowMath.viewProjection(
                bounds: target.bounds, sunDirection: sunTravelDirection
            )
            frame.views.append(matrix)
            frame.bias = max(
                frame.bias,
                FocusShadowMath.receiverBiasUnits / FocusShadowMath
                    .depthRange(bounds: target.bounds)
            )
            return AuxiliaryShadowView(
                slice: slice, viewProjection: matrix,
                excluding: RenderLayer.all.subtracting(.actors), drawsTerrain: false
            )
        }
        focusShadows = frame
        return views
    }

    /// Each drawn actor's world bounds, merged over its meshes.
    private func focusShadowTargets() -> [FocusShadowTarget] {
        var bounds: [UInt32: ModelBounds] = [:]
        for group in frameDrawGroups.shadowOpaque + frameDrawGroups.shadowAlphaTested
            where group.layer.contains(.actors) && group.castsShadows
        {
            for placed in group.instances where placed.owner != 0 {
                guard let own = drawn(placed).bounds else { continue }
                bounds[placed.owner] = bounds[placed.owner].map { $0.union(own) } ?? own
            }
        }
        return bounds.map { FocusShadowTarget(owner: $0.key, bounds: $0.value) }
    }
}
