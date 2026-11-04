import OpenSkyFormatsESM
import OpenSkyRenderCore
import simd

/// The sun, ambient light, sky, and fog one frame's uniforms take.
struct FrameLight {
    let sunDirection: SIMD3<Float>
    let sunColor: SIMD3<Float>
    let ambientColor: SIMD3<Float>
    let ambient: DirectionalAmbientColors
    /// The weather's sky palette; nil when the scene draws no sky.
    let weatherSky: ResolvedWeather?
    let fog: Renderer.FrameFog
}

extension Renderer {
    /// Weather is an exterior-only source: interiors keep their own baked `CELL` or
    /// `LGTM` lighting. The sky palette applies only when the scene draws a sky.
    func frameLight() -> FrameLight {
        let interior = activeLighting
        let weather = interior == nil ? frameInput.weather : nil
        let covered = effects.loadingCover != nil
        return FrameLight(
            sunDirection: interior?.directionalDirection ?? exteriorSunTravelDirection,
            sunColor: weather?.sunlightColor ?? interior?.directionalColor ?? camera.sunColor,
            ambientColor: weather?.ambientColor ?? interior?.ambientColor
                ?? camera.ambientColor,
            ambient: weather?.directionalAmbient ?? interior?.directionalAmbient ?? .black,
            weatherSky: scene.sky != nil && !covered ? weather : nil,
            fog: resolveFrameFog(weatherLight: covered ? nil : weather)
        )
    }

    var clampedGrassDrawDistance: Float {
        simd_clamp(
            grassDrawDistance,
            GrassRenderPolicy.minimumDrawDistance,
            GrassRenderPolicy.maximumDrawDistance
        )
    }

    /// The wind that bends grass this frame.
    var frameGrassWind: SIMD2<Float> {
        frameInput.wind.direction * frameInput.wind.speed
            * simd_clamp(grassWindScale, 0, GrassRenderPolicy.maximumWindScale)
    }

    /// Where the grass fade starts and where the grass is gone.
    var frameGrassFadeDistances: SIMD2<Float> {
        let distance = clampedGrassDrawDistance
        return SIMD2(
            max(
                distance * GrassRenderPolicy.fadeStartShare,
                GrassRenderPolicy.minimumDrawDistance * 0.5
            ),
            distance
        )
    }
}
