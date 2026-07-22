// Renderer-owned camera-following rain + snow volume (M7.4.1). Synthetic
// engine definitions feed the shared M7.3 particle simulator, GPU instance
// buffers, billboard shader, and alpha pipeline. No game texture is bundled:
// tiny streak/flake masks are generated at runtime.

import Metal
import simd

nonisolated struct PrecipitationRuntimeSnapshot: Equatable {
    let state: PrecipitationState
    let roofOccluded: Bool
    let rainLiveCount: Int
    let snowLiveCount: Int
}

nonisolated struct PrecipitationUpdate {
    let cameraPosition: SIMD3<Float>
    let state: PrecipitationState
    let wind: WindState
    let deltaTime: Float
    let exterior: Bool
    let enabled: Bool
    let collisionQuery: WalkController.CollisionQuery?
}

nonisolated final class PrecipitationVolume {
    private let rain: ParticlePlayback
    private let snow: ParticlePlayback
    private(set) var anchor: SIMD3<Float>?
    private(set) var snapshot = PrecipitationRuntimeSnapshot(
        state: .none, roofOccluded: false, rainLiveCount: 0, snowLiveCount: 0
    )
    private(set) var drawItems: [ParticlePlayback] = []

    var residencyAllocations: [MTLAllocation] {
        [rain.instanceBuffer, rain.texture, snow.instanceBuffer, snow.texture]
    }

    init(device: MTLDevice) throws {
        rain = try ParticlePlayback(
            device: device,
            definition: Self.rainDefinition,
            placementTransform: matrix_identity_float4x4,
            texture: Self.makeRainTexture(device: device),
            seed: 0x5241_494E,
            sourcePath: "(generated rain)"
        )
        snow = try ParticlePlayback(
            device: device,
            definition: Self.snowDefinition,
            placementTransform: matrix_identity_float4x4,
            texture: Self.makeSnowTexture(device: device),
            seed: 0x534E_4F57,
            sourcePath: "(generated snow)"
        )
    }

    func update(_ update: PrecipitationUpdate) {
        guard update.exterior, update.enabled else {
            clear()
            return
        }

        recenter(around: update.cameraPosition)
        let roofOccluded = update.state.intensity > 0 && update.collisionQuery.map {
            PrecipitationRoofOcclusion.isOccluded(above: update.cameraPosition, query: $0)
        } == true
        guard !roofOccluded else {
            rain.reset()
            snow.reset()
            drawItems = []
            snapshot = PrecipitationRuntimeSnapshot(
                state: update.state, roofOccluded: true, rainLiveCount: 0, snowLiveCount: 0
            )
            return
        }

        rain.advance(
            deltaTime: update.deltaTime,
            wind: update.wind,
            // Shared NIF fallback caps base birth rate at 60/s; weather
            // volumes need denser coverage across their much larger box.
            emissionScale: update.state.rainIntensity * 6
        )
        snow.advance(
            deltaTime: update.deltaTime,
            wind: update.wind,
            emissionScale: update.state.snowIntensity * 4
        )
        drawItems = [rain, snow]
        snapshot = PrecipitationRuntimeSnapshot(
            state: update.state,
            roofOccluded: false,
            rainLiveCount: rain.liveCount,
            snowLiveCount: snow.liveCount
        )
    }

    private func recenter(around cameraPosition: SIMD3<Float>) {
        let next = cameraPosition + SIMD3<Float>(0, 0, 600)
        let delta = next - (anchor ?? .zero)
        anchor = next
        rain.translate(by: delta)
        snow.translate(by: delta)
    }

    private func clear() {
        rain.reset()
        snow.reset()
        drawItems = []
        snapshot = PrecipitationRuntimeSnapshot(
            state: .none, roofOccluded: false, rainLiveCount: 0, snowLiveCount: 0
        )
    }
}

nonisolated extension PrecipitationVolume {
    fileprivate struct DefinitionConfig {
        let name: String
        let capacity: Int
        let speed: Float
        let speedVariation: Float
        let declinationVariation: Float
        let color: SIMD4<Float>
        let radius: Float
        let radiusVariation: Float
        let lifeSpan: Float
        let lifeVariation: Float
        let volume: SIMD3<Float>
        let windStrength: Float
    }

    fileprivate static let rainDefinition = definition(DefinitionConfig(
        name: "Rain volume",
        capacity: 1024,
        speed: 1900,
        speedVariation: 180,
        declinationVariation: 0.05,
        color: SIMD4(0.68, 0.78, 0.9, 0.72),
        radius: 12,
        radiusVariation: 3,
        lifeSpan: 0.8,
        lifeVariation: 0.1,
        volume: SIMD3(2200, 2200, 700),
        windStrength: 950
    ))

    fileprivate static let snowDefinition = definition(DefinitionConfig(
        name: "Snow volume",
        capacity: 768,
        speed: 360,
        speedVariation: 90,
        declinationVariation: 0.22,
        color: SIMD4(1, 1, 1, 0.88),
        radius: 18,
        radiusVariation: 6,
        lifeSpan: 3.2,
        lifeVariation: 0.5,
        volume: SIMD3(2400, 2400, 900),
        windStrength: 620
    ))

    fileprivate static func definition(_ config: DefinitionConfig) -> ParticleSystemDefinition {
        ParticleSystemDefinition(
            name: config.name,
            worldTransform: matrix_identity_float4x4,
            worldSpace: true,
            maxParticles: config.capacity,
            emitters: [ParticleEmitter(
                name: config.name,
                order: 0,
                active: true,
                speed: config.speed,
                speedVariation: config.speedVariation,
                declination: .pi,
                declinationVariation: config.declinationVariation,
                planarAngle: 0,
                planarAngleVariation: .pi,
                initialColor: config.color,
                initialRadius: config.radius,
                radiusVariation: config.radiusVariation,
                lifeSpan: config.lifeSpan,
                lifeSpanVariation: config.lifeVariation,
                shape: .box(
                    width: config.volume.x,
                    height: config.volume.y,
                    depth: config.volume.z
                )
            )],
            modifiers: [ParticleModifier(
                name: "Weather wind",
                order: 1,
                active: true,
                kind: .wind(strength: config.windStrength)
            )],
            subtextureOffsets: [],
            shaderPropertyRef: -1,
            alphaPropertyRef: -1,
            effectShader: nil,
            alphaProperty: nil
        )
    }

    fileprivate static func makeRainTexture(device: MTLDevice) throws -> MTLTexture {
        let width = 8
        let height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 2 ... 5 {
                let edge: Float = x == 2 || x == 5 ? 0.35 : 1
                let taper = sin(Float(y + 1) / Float(height + 1) * .pi)
                let alpha = UInt8(255 * edge * taper)
                let offset = (y * width + x) * 4
                pixels[offset] = 210
                pixels[offset + 1] = 228
                pixels[offset + 2] = 255
                pixels[offset + 3] = alpha
            }
        }
        return try makeTexture(
            device: device, width: width, height: height, pixels: pixels, label: "Rain streak"
        )
    }

    fileprivate static func makeSnowTexture(device: MTLDevice) throws -> MTLTexture {
        let size = 16
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let center = Float(size - 1) * 0.5
        for y in 0 ..< size {
            for x in 0 ..< size {
                let distance = simd_length(SIMD2(Float(x) - center, Float(y) - center)) / center
                let alpha = UInt8(255 * simd_clamp(1 - distance, 0, 1))
                let offset = (y * size + x) * 4
                pixels[offset] = 255
                pixels[offset + 1] = 255
                pixels[offset + 2] = 255
                pixels[offset + 3] = alpha
            }
        }
        return try makeTexture(
            device: device, width: size, height: size, pixels: pixels, label: "Snow flake"
        )
    }

    fileprivate static func makeTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixels: [UInt8],
        label: String
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocationFailed
        }
        texture.label = label
        pixels.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: width * 4
            )
        }
        return texture
    }
}
