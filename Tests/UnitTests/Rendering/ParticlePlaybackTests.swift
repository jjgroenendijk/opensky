// M7.3.2 CPU simulation + Metal billboard acceptance. Fixtures are engine
// values built in code; no extracted game data.

import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct ParticlePlaybackTests {
    @Test func deterministicSimulationUsesCapacityLifetimeAndWeatherWind() {
        let definition = makeDefinition(windStrength: 80)
        var calm = ParticleSimulator(
            definition: definition,
            placementTransform: matrix_identity_float4x4,
            seed: 42
        )
        var windy = calm
        for _ in 0 ..< 30 {
            calm.advance(deltaTime: 0.05, wind: .calm, emissionScale: 1)
            windy.advance(
                deltaTime: 0.05,
                wind: WindState(direction: SIMD2(1, 0), speed: 1, meanderRange: 0),
                emissionScale: 1
            )
        }

        #expect(!calm.particles.isEmpty)
        #expect(calm.particles.count <= definition.maxParticles)
        #expect(calm.particles.map(\.lifetime).allSatisfy { $0 > 0 })
        #expect(windy.particles.map(\.position.x).reduce(0, +)
            > calm.particles.map(\.position.x).reduce(0, +))

        var repeatRun = ParticleSimulator(
            definition: definition,
            placementTransform: matrix_identity_float4x4,
            seed: 42
        )
        for _ in 0 ..< 30 {
            repeatRun.advance(deltaTime: 0.05, wind: .calm, emissionScale: 1)
        }
        #expect(repeatRun.particles == calm.particles)
    }

    @Test func blendClassificationCoversEffectPipelines() throws {
        #expect(ParticleBlendMode(alpha: nil) == .alpha)
        #expect(try blendMode(source: 6, destination: 0) == .additive)
        #expect(try blendMode(source: 0, destination: 0) == .additiveOne)
        #expect(try blendMode(source: 4, destination: 1) == .multiply)
        #expect(try blendMode(source: 6, destination: 7) == .alpha)
    }

    @Test(.enabled(if: Self.device != nil))
    @MainActor
    func billboardFramesChangeAtExactSimulationTimes() throws {
        let device = try #require(Self.device)
        let texture = try whiteTexture(device: device)
        let playback = try ParticlePlayback(
            device: device,
            definition: makeDefinition(windStrength: 0),
            placementTransform: matrix_identity_float4x4,
            texture: texture,
            seed: 7
        )
        let scene = RenderScene(instances: [], particles: [playback])
        let camera = SceneCamera(
            eye: SIMD3(-300, 0, 80),
            target: SIMD3(0, 0, 80),
            sunDirection: SIMD3(0, 0, -1),
            sunColor: .one,
            ambientColor: .one
        )
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 256, height: 256), device: device)
        view.isPaused = true
        let renderer = try Renderer(view: view, scene: scene, camera: camera)
        let first = try pixels(renderer.renderOffscreen(
            width: 256, height: 256, animationTime: 0.5
        ))
        let second = try pixels(renderer.renderOffscreen(
            width: 256, height: 256, animationTime: 1.0
        ))
        #expect(first != second)
        #expect(playback.liveCount > 0)
    }

    private static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private func makeDefinition(windStrength: Float) -> ParticleSystemDefinition {
        ParticleSystemDefinition(
            name: "Synthetic flame",
            worldTransform: matrix_identity_float4x4,
            worldSpace: true,
            maxParticles: 32,
            emitters: [ParticleEmitter(
                name: "Flame emitter",
                order: 0,
                active: true,
                speed: 80,
                speedVariation: 8,
                declination: 0,
                declinationVariation: 0.15,
                planarAngle: 0,
                planarAngleVariation: .pi,
                initialColor: SIMD4(1, 0.5, 0.1, 1),
                initialRadius: 45,
                radiusVariation: 4,
                lifeSpan: 1.2,
                lifeSpanVariation: 0.1,
                shape: .sphere(radius: 12)
            )],
            modifiers: [ParticleModifier(
                name: "Wind",
                order: 1,
                active: true,
                kind: .wind(strength: windStrength)
            )],
            subtextureOffsets: [],
            shaderPropertyRef: -1,
            alphaPropertyRef: -1,
            effectShader: nil,
            alphaProperty: nil
        )
    }

    private func blendMode(source: UInt16, destination: UInt16) throws -> ParticleBlendMode {
        let flags = UInt16(1) | source << 1 | destination << 5
        var reader = BinaryReader(NIFFixture.header())
        let header = try NIFHeader(reader: &reader)
        let alpha = try NIFAlphaProperty(
            data: NIFFixture.niAlphaProperty(flags: flags, threshold: 0),
            header: header
        )
        return ParticleBlendMode(alpha: alpha)
    }

    private func whiteTexture(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        var white = SIMD4<UInt8>(repeating: 255)
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &white,
            bytesPerRow: 4
        )
        return texture
    }

    @MainActor
    private func pixels(_ texture: MTLTexture) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        result.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return result
    }
}
