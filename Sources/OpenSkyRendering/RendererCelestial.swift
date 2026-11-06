// Draws the stars, the aurora, the sun glare, the sun, and the moons between the sky
// gradient and the cloud layers (docs/engine/celestial-sky.md "Drawing").

import Metal
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

extension Renderer {
    /// OpenSky's card sizes, as tangents of the half angle: no setting gives them.
    static let sunHalfSize: Float = 0.06
    static let glareHalfSize: Float = 0.5

    /// This frame's sky objects: exterior weather only, and only under a sky.
    var frameCelestial: CelestialSky? {
        guard scene.sky != nil, scene.lighting == nil else { return nil }
        return frameInput.celestial
    }

    /// The direction sunlight travels outdoors: the sun path when there is one.
    public var exteriorSunTravelDirection: SIMD3<Float> {
        frameCelestial?.lightDirection ?? camera.sunDirection
    }

    /// Drains finished sky object loads and requests what this frame needs.
    public func prepareCelestial() {
        guard let skyCelestial, let sky = frameCelestial else { return }
        let added = skyCelestial.prepare(sky)
        guard !added.isEmpty else { return }
        residencySet.addAllocations(added)
        residencySet.commit()
    }

    func encodeCelestial(state: inout ScenePassState) {
        guard let skyCelestial else { return }
        var drawer = SkyObjectDrawer(renderer: self, sky: skyCelestial, slot: state.slot)
        defer {
            skyCelestial.drawnObjectCount = drawer.drawn
            state.stats.drawCalls += drawer.drawn
        }
        guard let sky = frameCelestial else { return }
        let weather = frameInput.weather
        let encoder = state.encoder
        if let stars = weather?.stars, simd_reduce_max(stars) > 0.001 {
            let rotation = float4x4(simd_quatf(angle: sky.starsAngle, axis: sky.starsAxis))
            drawer.mesh(sky.nightSkyModel, rotation: rotation, tint: SIMD4(stars, 1), encoder)
        }
        for aurora in sky.auroras {
            let tint = SIMD4<Float>(1, 1, 1, aurora.alpha)
            let rotation = float4x4(simd_quatf(angle: aurora.yaw, axis: SIMD3(0, 0, 1)))
            drawer.mesh(aurora.model, rotation: rotation, tint: tint, encoder)
        }
        if sky.sunAlpha > 0.001 {
            let glare = SkyCard(
                texture: sky.glareTexture, direction: sky.sunDirection,
                halfSize: Self.glareHalfSize * sky.glareScale,
                tint: SIMD4(weather?.sunGlare ?? SIMD3(repeating: 1), sky.sunAlpha), mode: .additive
            )
            drawer.card(glare, encoder)
            let sun = SkyCard(
                texture: sky.sunTexture, direction: sky.sunDirection, halfSize: Self.sunHalfSize,
                tint: SIMD4(weather?.sun ?? SIMD3(repeating: 1), sky.sunAlpha), mode: .additive
            )
            drawer.card(sun, encoder)
        }
        for moon in sky.moons where moon.alpha > 0.001 {
            // The shadow paints the sky colour back over the stars behind the moon.
            let behind = simd_mix(
                weather?.skyLower ?? .zero, weather?.skyUpper ?? .zero,
                SIMD3(repeating: simd_clamp(moon.direction.z * 2, 0, 1))
            )
            drawer.card(SkyCard(
                texture: CelestialSky.moonShadowTexture, direction: moon.direction,
                halfSize: moon.halfSize, tint: SIMD4(behind, moon.alpha), mode: .alphaOnly
            ), encoder)
            // The moon adds its weather colour, dark by day, so a day moon is faint.
            drawer.card(SkyCard(
                texture: moon.texture, direction: moon.direction, halfSize: moon.halfSize,
                tint: SIMD4(weather?.moonGlare ?? SIMD3(repeating: 1), moon.alpha),
                mode: .additive
            ), encoder)
        }
    }
}

/// One camera-facing card: the sun, its glare, or a moon.
struct SkyCard {
    /// Relative to `textures\`.
    let texture: String?
    let direction: SIMD3<Float>
    let halfSize: Float
    let tint: SIMD4<Float>
    let mode: Mode

    enum Mode {
        case additive, cover, alphaOnly

        var flags: UInt32 {
            switch self {
            case .additive: UInt32(SkyObjectFlag.additive.rawValue)
            case .cover: 0
            case .alphaOnly: UInt32(SkyObjectFlag.alphaOnly.rawValue)
            }
        }
    }
}

/// Writes one uniform slot per draw and binds its textures.
struct SkyObjectDrawer {
    let renderer: Renderer
    let sky: SkyCelestial
    let slot: Int
    private(set) var drawn = 0

    mutating func mesh(
        _ model: String?, rotation: float4x4, tint: SIMD4<Float>,
        _ encoder: MTL4RenderCommandEncoder
    ) {
        guard let mesh = sky.mesh(key: model.flatMap(SkyCelestial.meshKey)) else { return }
        encoder.setRenderPipelineState(renderer.skyLayerPipelines.objects.mesh)
        renderer.argumentTable.setAddress(
            mesh.vertices.gpuAddress, index: BufferIndex.vertices.rawValue
        )
        for shape in mesh.shapes {
            guard let texture = sky.texture(key: shape.texture) else { continue }
            let palette = sky.texture(key: shape.palette)
            let shading = shape.shading(at: renderer.animationTime)
            let effect = RenderEffectMaterial(shading: shading.effect, palette: palette)
            var uniforms = SkyObjectUniforms()
            uniforms.uvTransform = shading.uvTransform
            uniforms.rotation = rotation
            uniforms.color = tint
            uniforms.falloff = effect.falloff
            uniforms.baseColor = effect.baseColor
            uniforms.baseColorScale = effect.baseColorScale
            uniforms.flags = UInt32(SkyObjectFlag.additive.rawValue)
            // The sky has no scene depth or light to fade or tint by.
            let unused = EffectFlag.soft.rawValue | EffectFlag.lit.rawValue
                | EffectFlag.externalEmittance.rawValue
            uniforms.effectFlags = effect.flags & ~UInt32(unused)
            guard bind(&uniforms, texture: texture, palette: palette) else { return }
            let stride = MemoryLayout<UInt32>.stride
            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: shape.indices.count,
                indexType: .uint32,
                indexBuffer: mesh.indices.gpuAddress + UInt64(shape.indices.lowerBound * stride),
                indexBufferLength: shape.indices.count * stride
            )
        }
    }

    mutating func card(_ card: SkyCard, _ encoder: MTL4RenderCommandEncoder) {
        guard let texture = sky.texture(key: card.texture.flatMap(SkyCelestial.textureKey))
        else { return }
        let direction = simd_normalize(card.direction)
        let worldUp = abs(direction.z) > 0.99 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(0, 0, 1)
        let right = simd_normalize(simd_cross(direction, worldUp))
        let up = simd_cross(right, direction)
        var uniforms = SkyObjectUniforms()
        uniforms.color = card.tint
        uniforms.center = SIMD4(direction, card.halfSize)
        uniforms.right = SIMD4(right, 0)
        uniforms.up = SIMD4(up, 0)
        uniforms.flags = card.mode.flags
        encoder.setRenderPipelineState(renderer.skyLayerPipelines.objects.card)
        guard bind(&uniforms, texture: texture, palette: nil) else { return }
        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 6)
    }

    /// False once this frame's uniform slots are spent.
    private mutating func bind(
        _ uniforms: inout SkyObjectUniforms, texture: MTLTexture, palette: MTLTexture?
    ) -> Bool {
        guard drawn < SkyCelestial.maximumDraws else { return false }
        let offset = SkyCelestial.uniformStride * (slot * SkyCelestial.maximumDraws + drawn)
        sky.uniforms.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<SkyObjectUniforms>.size)
        let table = renderer.argumentTable
        table.setAddress(
            sky.uniforms.gpuAddress + UInt64(offset), index: BufferIndex.drawUniforms.rawValue
        )
        table.setTexture(texture.gpuResourceID, index: TextureIndex.diffuse.rawValue)
        table.setTexture(
            (palette ?? texture).gpuResourceID, index: TextureIndex.effectPalette.rawValue
        )
        drawn += 1
        return true
    }
}
