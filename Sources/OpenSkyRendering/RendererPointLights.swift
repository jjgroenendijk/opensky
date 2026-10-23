// The nearest point lights of one draw, written into the point light ring.

import Metal
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
    /// Selects and writes the nearest supported point lights for one draw.
    func writePointLights(
        near position: SIMD3<Float>,
        slot: Int,
        draw: Int
    ) -> PointLightRange {
        let limit = LightingConstant.maxPointLights.rawValue
        let pick = pointLightPick(near: position, limit: limit)
        let stride = MemoryLayout<PointLightUniform>.stride
        let first = (slot * drawUniformSlotCapacity + draw) * limit
        let transient = transientPointLights.prefix(limit)
        let scenePicks = (0 ..< min(pick.count, limit - transient.count)).map {
            scene.pointLights[Int(pick.indices[$0])]
        }
        let picked = Array(transient) + scenePicks
        let ordered = picked.filter { !$0.castsShadows } + picked.filter(\.castsShadows)
        for (index, light) in ordered.enumerated() {
            let live = light.animated(at: animationTime, enabled: lightAnimationEnabled)
            var uniform = PointLightUniform(
                positionRadius: SIMD4(live.position, light.radius),
                colorFalloff: SIMD4(live.color, light.falloffExponent)
            )
            pointLightBuffer.contents().advanced(by: (first + index) * stride)
                .copyMemory(from: &uniform, byteCount: MemoryLayout<PointLightUniform>.size)
        }
        return PointLightRange(
            count: ordered.count,
            unshadowedCount: ordered.count { !$0.castsShadows },
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
