// Camera-following rain and snow, fed through the shared particle simulator and
// billboard pipeline. No game texture: streak and flake masks are generated at runtime.

public import Metal
import OpenSkyFormatsMesh
public import OpenSkyRenderCore
import OpenSkyRenderResources
import simd

nonisolated public struct PrecipitationRuntimeSnapshot: Equatable, Sendable {
    public let state: PrecipitationState
    public let roofOccluded: Bool
    public let rainLiveCount: Int
    public let snowLiveCount: Int

    public init(
        state: PrecipitationState,
        roofOccluded: Bool,
        rainLiveCount: Int,
        snowLiveCount: Int
    ) {
        self.state = state
        self.roofOccluded = roofOccluded
        self.rainLiveCount = rainLiveCount
        self.snowLiveCount = snowLiveCount
    }
}

/// True when something solid is above the point, so no rain falls there.
public typealias PrecipitationRoofCheck = (SIMD3<Float>) -> Bool

nonisolated struct PrecipitationUpdate {
    let cameraPosition: SIMD3<Float>
    let state: PrecipitationState
    let wind: WindState
    let deltaTime: Float
    let exterior: Bool
    let enabled: Bool
    /// Nil when nothing hides rain under a roof, or when the occlusion map does it per drop.
    let roofAbove: PrecipitationRoofCheck?
}

nonisolated public final class PrecipitationVolume {
    private let device: any MTLDevice
    private let rain: ParticlePlayback
    private var snow: ParticlePlayback
    private let generatedSnowTexture: any MTLTexture
    /// The `SPGD` look the snow draws with; nil for the generated flake.
    public private(set) var snowLook: PrecipitationLook?
    private(set) var anchor: SIMD3<Float>?
    public private(set) var snapshot = PrecipitationRuntimeSnapshot(
        state: .none, roofOccluded: false, rainLiveCount: 0, snowLiveCount: 0
    )
    private(set) var drawItems: [ParticlePlayback] = []
    /// Unit direction the stronger of rain and snow falls, for the roof occlusion view.
    private(set) var fallDirection = SIMD3<Float>(0, 0, -1)
    /// The active weather's `SPGD` scales; the hand-tuned look when it names none.
    public var tuning = PrecipitationTuning.fallback {
        didSet {
            rain.setSpawnScale(tuning.rain)
            snow.setSpawnScale(tuning.snow)
            rain.setStreakAspect(tuning.rainStreakAspect)
        }
    }

    public var residencyAllocations: [any MTLAllocation] {
        rain.residencyAllocations + snow.residencyAllocations
    }

    public init(device: any MTLDevice) throws {
        self.device = device
        generatedSnowTexture = try Self.makeSnowTexture(device: device)
        rain = try ParticlePlayback(
            device: device,
            definition: Self.rainDefinition,
            placementTransform: matrix_identity_float4x4,
            texture: Self.makeRainTexture(device: device),
            effect: .precipitation,
            seed: 0x5241_494E,
            sourcePath: "(generated rain)"
        )
        snow = try Self.makeSnow(
            device: device, texture: generatedSnowTexture, look: nil
        )
        rain.setStreakAspect(tuning.rainStreakAspect)
    }

    private static func makeSnow(
        device: any MTLDevice, texture: any MTLTexture, look: PrecipitationLook?
    ) throws -> ParticlePlayback {
        try ParticlePlayback(
            device: device,
            definition: definition(snowConfig, cells: look?.cellRects ?? []),
            placementTransform: matrix_identity_float4x4,
            texture: texture,
            effect: .precipitation,
            seed: 0x534E_4F57,
            sourcePath: look?.texturePath ?? "(generated snow)"
        )
    }

    /// Draws snow with `look`'s texture and cells, or the generated flake for nil. The
    /// falling flakes start over. Returns the allocations the swap retired and added.
    func setSnowLook(
        _ look: PrecipitationLook?, texture: any MTLTexture?
    ) throws -> (retired: [any MTLAllocation], added: [any MTLAllocation]) {
        let look = texture == nil ? nil : look
        guard look != snowLook else { return ([], []) }
        let retired = snow.residencyAllocations
        snow = try Self.makeSnow(
            device: device, texture: texture ?? generatedSnowTexture, look: look
        )
        snow.setSpawnScale(tuning.snow)
        // A new playback's emitter starts at the origin; the volume sits at the anchor.
        snow.translate(by: anchor ?? .zero)
        snowLook = look
        if drawItems.count == 2 {
            drawItems = [rain, snow]
        }
        return (retired, snow.residencyAllocations)
    }

    func update(_ update: PrecipitationUpdate) {
        guard update.exterior, update.enabled else {
            clear()
            return
        }

        recenter(around: update.cameraPosition)
        let roofOccluded = update.state.intensity > 0 && update
            .roofAbove?(update.cameraPosition) == true
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
            emissionScale: update.state.rainIntensity * PrecipitationBase.rain.emission
                * tuning.rain.density
        )
        snow.advance(
            deltaTime: update.deltaTime,
            wind: update.wind,
            emissionScale: update.state.snowIntensity * PrecipitationBase.snow.emission
                * tuning.snow.density
        )
        drawItems = [rain, snow]
        fallDirection = update.state.rainIntensity >= update.state.snowIntensity
            ? Self.fallDirection(of: Self.rainDefinition, wind: update.wind)
            : Self.fallDirection(of: Self.snowDefinition, wind: update.wind)
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
        let jumped = anchor != nil && simd_length(delta) > Self.teleportDistance
        anchor = next
        rain.translate(by: delta)
        snow.translate(by: delta)
        // Flakes from before a teleport belong to the old place and its weather.
        if jumped {
            rain.reset()
            snow.reset()
        }
    }

    /// Half the smallest volume width: no walk or flight covers it in one frame.
    static let teleportDistance: Float = 1100

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
        speed: PrecipitationBase.rain.speed,
        speedVariation: 180,
        declinationVariation: 0.05,
        color: SIMD4(0.68, 0.78, 0.9, 0.72),
        radius: PrecipitationBase.rain.radius,
        radiusVariation: 3,
        lifeSpan: 0.8,
        lifeVariation: 0.1,
        volume: SIMD3(2200, 2200, 700),
        windStrength: 950
    ))

    fileprivate static let snowDefinition = definition(snowConfig)

    fileprivate static let snowConfig = DefinitionConfig(
        name: "Snow volume",
        capacity: 768,
        speed: PrecipitationBase.snow.speed,
        speedVariation: 90,
        declinationVariation: 0.22,
        // The sprite is unlit, so a grey tint keeps a near flake below the sky's brightness.
        color: SIMD4(0.8, 0.82, 0.86, 0.8),
        radius: PrecipitationBase.snow.radius,
        radiusVariation: 2,
        lifeSpan: 3.2,
        lifeVariation: 0.5,
        volume: SIMD3(2400, 2400, 900),
        windStrength: 620
    )

    /// The mean path of a drop: its fall speed down and the wind's push over half its life.
    static func fallDirection(
        of definition: ParticleSystemDefinition, wind: WindState
    ) -> SIMD3<Float> {
        guard
            let emitter = definition.emitters.first,
            case let .wind(strength)? = definition.modifiers.first?.kind
        else { return SIMD3(0, 0, -1) }
        let push = wind.direction * wind.speed * strength * emitter.lifeSpan * 0.5
        let path = SIMD3(push.x, push.y, -max(emitter.speed, 1))
        return simd_normalize(path)
    }

    fileprivate static func definition(
        _ config: DefinitionConfig, cells: [SIMD4<Float>] = []
    ) -> ParticleSystemDefinition {
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
            subtextureOffsets: cells,
            shaderPropertyRef: -1,
            alphaPropertyRef: -1,
            effectShader: nil,
            alphaProperty: nil
        )
    }

    fileprivate static func makeRainTexture(device: any MTLDevice) throws -> any MTLTexture {
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
            device: device, size: (width, height), pixels: pixels, label: "Rain streak"
        )
    }

    fileprivate static func makeSnowTexture(device: any MTLDevice) throws -> any MTLTexture {
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
            device: device, size: (size, size), pixels: pixels, label: "Snow flake"
        )
    }

    fileprivate static func makeTexture(
        device: any MTLDevice,
        size: (width: Int, height: Int),
        pixels: [UInt8],
        label: String
    ) throws -> any MTLTexture {
        let (width, height) = size
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
            unsafe texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: width * 4
            )
        }
        return texture
    }
}
