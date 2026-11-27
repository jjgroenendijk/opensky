// The nearest point lights of one draw, written into the point light ring.

import Metal
import OpenSkyRenderCore
import OpenSkyShaderTypes
import simd

/// Where one draw's lights sit in the ring. Lights that cast no shadow come first, so
/// an effect-lit shape reads only them.
nonisolated struct PointLightRange: Equatable, Sendable {
    var count = 0
    var unshadowedCount = 0
    var byteOffset = 0
}

extension Renderer {
    /// Selects and writes the nearest supported point lights for one draw. A cover is
    /// lit by its own lights only.
    func writePointLights(
        near position: SIMD3<Float>,
        slot: Int,
        draw: Int
    ) -> PointLightRange {
        let limit = LightingConstant.maxPointLights.rawValue
        let cover = effects.loadingCover
        let pick = cover?.nearestPointLightPick(to: position, limit: limit)
            ?? pointLightPick(near: position, limit: limit)
        let lights = activePointLights
        let stride = MemoryLayout<PointLightUniform>.stride
        let first = (slot * drawUniformSlotCapacity + draw) * limit
        let transient = cover == nil
            ? transientPointLights.prefix(limit).map { (light: $0, index: Int?.none) } : []
        let scenePicks = (0 ..< min(pick.count, limit - transient.count)).map {
            let index = Int(pick.indices[$0])
            return (light: lights[index], index: Int?.some(index))
        }
        let picked = transient + scenePicks
        let ordered = picked.filter { !$0.light.castsShadows }
            + picked.filter(\.light.castsShadows)
        for (index, entry) in ordered.enumerated() {
            let light = entry.light
            let live = light.animated(at: animationTime, enabled: lightAnimationEnabled)
            var uniform = PointLightUniform(
                positionRadius: SIMD4(live.position, light.radius),
                colorFalloff: SIMD4(live.color, light.falloffExponent),
                shadow: pointShadows.uniform(
                    sceneIndex: entry.index, radius: light.radius, depthBias: light.shadowDepthBias
                )
            )
            unsafe pointLightBuffer.contents().advanced(by: (first + index) * stride)
                .copyMemory(from: &uniform, byteCount: MemoryLayout<PointLightUniform>.size)
        }
        return PointLightRange(
            count: ordered.count,
            unshadowedCount: ordered.count { !$0.light.castsShadows },
            byteOffset: first * stride
        )
    }

    /// Group and terrain centers repeat every frame, so their picks are kept per scene.
    /// Moving centers, such as the player body, would grow the cache, so it has a cap.
    private func pointLightPick(near position: SIMD3<Float>, limit: Int) -> PointLightPick {
        if let cached = pointLightPicks[position] {
            return cached
        }
        if pointLightPicks.count >= Self.pointLightPickCacheLimit {
            pointLightPicks.removeAll(keepingCapacity: true)
        }
        let pick = scene.nearestPointLightPick(to: position, limit: limit)
        pointLightPicks[position] = pick
        return pick
    }
}
