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
    var strengths = SIMD4<Float>(repeating: 0)
    var extents = SIMD4<Float>(repeating: 1)
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
        let picks = FocusShadowMath.pick(
            focusShadowTargets(), viewer: frameInput.view.position, count: count,
            resolution: shadowSettings.resolution
        )
        var frame = FocusShadowFrame()
        let views = picks.enumerated().map { slice, pick in
            let target = pick.target
            let matrix = FocusShadowMath.viewProjection(
                bounds: target.bounds, sunDirection: sunTravelDirection
            )
            let extent = min(Float(pick.size) / Float(AuxiliaryShadowResources.size), 1)
            frame.views.append(matrix)
            frame.strengths[slice] = pick.strength
            frame.extents[slice] = extent
            frame.bias = max(
                frame.bias,
                FocusShadowMath.receiverBiasUnits / FocusShadowMath
                    .depthRange(bounds: target.bounds)
            )
            return AuxiliaryShadowView(
                slice: slice, viewProjection: matrix,
                excluding: RenderLayer.all.subtracting(.actors), drawsTerrain: false,
                extent: extent
            )
        }
        focusShadows = frame
        return views
    }

    /// Each drawn actor's world bounds, merged over its meshes.
    private func focusShadowTargets() -> [FocusShadowTarget] {
        var bounds: [UInt32: ModelBounds] = [:]
        // Walks both lists in place: joining them copied every draw group each frame.
        for list in [frameDrawGroups.shadowOpaque, frameDrawGroups.shadowAlphaTested] {
            for group in list where group.layer.contains(.actors) && group.castsShadows {
                for placed in group.instances where placed.owner != 0 {
                    guard let own = drawn(placed).bounds else { continue }
                    if let merged = bounds[placed.owner] {
                        bounds[placed.owner] = merged.union(own)
                    } else {
                        bounds[placed.owner] = own
                    }
                }
            }
        }
        var targets: [FocusShadowTarget] = []
        targets.reserveCapacity(bounds.count)
        for (owner, box) in bounds {
            targets.append(FocusShadowTarget(owner: owner, bounds: box))
        }
        return targets
    }
}
