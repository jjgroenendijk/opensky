// Rings on the water and the view from under it: splashes and waders start rings,
// rain adds its own, and a camera below a water surface sees the water's under-water
// fog (docs/rendering/water.md).

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRenderCore
import OpenSkyShaderTypes
import simd

nonisolated extension WaterRippleField {
    /// Fills the shader's fixed ring array, which Swift sees as a tuple; unused rings are zero.
    static func write(_ rings: [SIMD4<Float>], into storage: inout some Any) {
        withUnsafeMutableBytes(of: &storage) { raw in
            let slots = raw.bindMemory(to: SIMD4<Float>.self)
            for index in slots.indices {
                slots[index] = index < rings.count ? rings[index] : .zero
            }
        }
    }
}

extension Renderer {
    /// A splash at the surface: a heavy one is strength 1.
    public func addWaterRipple(at position: SIMD3<Float>, strength: Float) {
        waterRipples.add(at: position, strength: strength, time: animationTime)
    }

    /// The actors and bodies standing in water this frame; each starts a ring per step.
    public func updateWaders(_ waders: [(key: ReferenceKey, position: SIMD3<Float>)]) {
        for wader in waders {
            waterRipples.wade(wader.key, at: wader.position, time: animationTime)
        }
        waterRipples.keepWaders(Set(waders.map(\.key)))
    }

    /// How hard it rains on exterior water, 0 to 1.
    var frameRainOnWater: Float {
        guard scene.lighting == nil else { return 0 }
        return frameInput.weather?.precipitation.rainIntensity ?? 0
    }

    /// The `INAM` image space of the water over the camera; nil above water.
    public var cameraWaterImageSpace: FormID? {
        waterAboveCamera?.underwaterImageSpace
    }

    /// The look of the water whose surface is over the camera, or nil above water.
    var waterAboveCamera: WaterLook? {
        let camera = frameInput.view.position
        for item in scene.water {
            guard let bounds = item.bounds else { continue }
            let inside = camera.x >= bounds.min.x && camera.x <= bounds.max.x
                && camera.y >= bounds.min.y && camera.y <= bounds.max.y
            if inside, camera.z < bounds.max.z {
                return item.look
            }
        }
        return nil
    }

    /// The `WATR` under-water fog: from the near to the far plane toward the deep
    /// colour, up to the fog amount. A water with no amount fogs fully.
    func underwaterFog(_ look: WaterLook) -> FrameFog {
        let fog = look.shading.underwaterFog
        let far = max(fog.y, fog.x + 1)
        let amount = fog.z > 0 ? min(fog.z, 1) : 1
        return FrameFog(
            nearColor: look.deepColor, farColor: look.deepColor,
            distances: SIMD4(max(fog.x, 0), far, 1, amount), enabled: 1
        )
    }
}
