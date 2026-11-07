import Metal
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
        let scales = lightScales
        let aboveWater = resolveFrameFog(weatherLight: covered ? nil : weather)
        let sun = weather?.sunlightColor ?? interior?.directionalColor ?? camera.sunColor
        return FrameLight(
            sunDirection: interior?.directionalDirection ?? exteriorSunTravelDirection,
            sunColor: sun * scales.sunlight,
            ambientColor: weather?.ambientColor ?? interior?.ambientColor
                ?? camera.ambientColor,
            ambient: weather?.directionalAmbient ?? interior?.directionalAmbient ?? .black,
            weatherSky: scene.sky != nil && !covered
                ? weather?.liftingSky(scale: EyeAdaptation.sceneScale, lift: scales.skyLift) : nil,
            fog: waterAboveCamera.map(underwaterFog) ?? aboveWater
        )
    }

    /// The `IMGS` sunlight scale multiplies the sun colour. The sky scale, times the scene
    /// scale, is added to the dome and cloud colours (docs/rendering/image-space.md).
    var lightScales: (sunlight: Float, skyLift: Float) {
        let hdr = frameInput.imageSpace.current(withScreenFade: false).hdr
        func finite(_ value: Float) -> Float {
            value.isFinite ? simd_clamp(value, 0, 8) : 1
        }
        let lift = hdr.skyScale.isFinite ? simd_clamp(hdr.skyScale, 0, 8) : 0
        return (finite(hdr.sunlightScale), lift * EyeAdaptation.sceneScale)
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

    /// The wind that sways trees this frame.
    var frameTreeWind: SIMD4<Float> {
        let direction = frameInput.wind.direction
        return SIMD4(
            direction.x, direction.y, simd_clamp(frameInput.wind.speed, 0, 1),
            TreeWindPolicy.leafFadeDistance
        )
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
