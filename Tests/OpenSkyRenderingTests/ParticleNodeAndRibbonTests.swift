// Emitters that ride moved nodes, the inherit object's velocity, the spin axis of mesh
// particles, and lightning bolts.

@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
@testable import OpenSkyRenderCore
@testable import OpenSkyRendering
import simd
import Testing

struct ParticleNodeAndRibbonTests {
    private static func translation(_ offset: SIMD3<Float>) -> float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(offset, 1)
        return matrix
    }

    @Test func anEmitterBelowAMovedNodeEmitsWhereTheNodeIsNow() {
        var definition = Self.definition(modifiers: [], speed: 0)
        definition.ancestorNodes = ["arm", "scene"]
        var simulator = ParticleSimulator(
            definition: definition, placementTransform: matrix_identity_float4x4, seed: 3
        )
        simulator.move(
            to: matrix_identity_float4x4, nodeDeltas: ["arm": Self.translation([0, 0, 100])]
        )
        simulator.advance(deltaTime: 0.1, wind: .calm, emissionScale: 1)
        #expect(!simulator.particles.isEmpty)
        for particle in simulator.particles {
            #expect(abs(particle.position.z - 100) < 1.5)
        }
    }

    @Test func newParticlesTakeTheVelocityOfTheInheritObject() {
        var inherit = ParticleInheritVelocity(chance: 100, multiplier: 1, variation: 0)
        inherit.objectNodes = ["tip"]
        var simulator = ParticleSimulator(
            definition: Self.definition(modifiers: [Self.modifier(.inheritVelocity(inherit))], speed: 0),
            placementTransform: matrix_identity_float4x4, seed: 5
        )
        // The system stays put while its inherit object swings 20 units a step along +Y.
        for step in 0 ... 10 {
            let swing = Self.translation([0, Float(step) * 20, 0])
            simulator.move(to: matrix_identity_float4x4, nodeDeltas: ["tip": swing])
            simulator.advance(deltaTime: 0.1, wind: .calm, emissionScale: 1)
        }
        let young = simulator.particles.filter { $0.age < 0.5 }
        #expect(!young.isEmpty)
        for particle in young {
            #expect(simd_distance(particle.velocity, SIMD3(0, 200, 0)) < 1e-3)
        }
    }

    @Test func aSetAxisSpinsEachMeshParticleAboutThatAxis() {
        let rotation = ParticleRotation(
            speed: 1, speedVariation: 0, angle: .pi / 2, angleVariation: 0,
            randomSpeedSign: false, randomAxis: false, axis: SIMD3(0, 2, 0)
        )
        var simulator = ParticleSimulator(
            definition: Self.definition(modifiers: [Self.modifier(.rotation(rotation))]),
            placementTransform: matrix_identity_float4x4, seed: 9
        )
        simulator.advance(deltaTime: 0.1, wind: .calm, emissionScale: 1)
        let particle = simulator.particles.first
        #expect(particle.map { simd_distance($0.axis, [0, 1, 0]) < 1e-5 } == true)
        if var turned = particle {
            turned.rotation = .pi / 2
            turned.radius = 1
            let matrix = ParticlePlayback.meshTransform(of: turned)
            let xAxis = SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
            // A quarter turn about +Y takes +X to -Z.
            #expect(simd_distance(xAxis, [0, 0, -1]) < 1e-5)
        }
    }

    @Test func aRandomAxisGivesEachParticleItsOwnAxis() {
        let rotation = ParticleRotation(
            speed: 1, speedVariation: 0, angle: 0, angleVariation: 0,
            randomSpeedSign: false, randomAxis: true, axis: SIMD3(1, 0, 0)
        )
        var simulator = ParticleSimulator(
            definition: Self.definition(modifiers: [Self.modifier(.rotation(rotation))]),
            placementTransform: matrix_identity_float4x4, seed: 11
        )
        for _ in 0 ..< 5 {
            simulator.advance(deltaTime: 0.1, wind: .calm, emissionScale: 1)
        }
        let axes = simulator.particles.map(\.axis)
        #expect(axes.count > 2)
        #expect(axes.allSatisfy { abs(simd_length($0) - 1) < 1e-4 })
        #expect(Set(axes.map { Int($0.x * 1000) }).count > 1)
    }

    @Test func aLightningBoltReachesItsLengthAndCrawlsOverTime() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(controllerRef: 1)
                )),
                NIFFixture.Block(
                    "BSProceduralLightningController",
                    NIFParticleParameterFixture.lightningController(
                        targetRef: 0, subdivisions: 4, branches: 0, length: 512, width: 16
                    )
                )
            ],
            roots: [0]
        ))
        let bolt = try #require(try file.particleSystems().first?.lightning)
        let generator = LightningBolt(parameters: bolt, seed: 1)
        let now = generator.segments(at: 0, color: SIMD4(repeating: 1))
        // Four halvings make 16 bands on the main bolt; no branches were asked for.
        #expect(now.count == 16)
        #expect(simd_length(now[0].start) < 1e-4)
        #expect(abs((now.last?.end.y ?? 0) - 512) < 1e-3)
        #expect(now.last?.endWidth == 0, "the main bolt fades to a point")
        let later = generator.segments(at: 0.05, color: SIMD4(repeating: 1))
        #expect(later.count == now.count)
        #expect(zip(now, later).contains { simd_distance($0.end, $1.end) > 1e-3 })
        #expect(generator.segments(at: 0, color: SIMD4(repeating: 1)) == now)
    }

    private static func modifier(_ kind: ParticleModifier.Kind) -> ParticleModifier {
        ParticleModifier(name: nil, order: 0, active: true, kind: kind)
    }

    private static func definition(
        modifiers: [ParticleModifier], speed: Float = 10
    ) -> ParticleSystemDefinition {
        ParticleSystemDefinition(
            name: "Synthetic sparks",
            worldTransform: matrix_identity_float4x4,
            worldSpace: true,
            maxParticles: 64,
            emitters: [ParticleEmitter(
                name: "Sparks", order: 0, active: true, speed: speed, speedVariation: 0,
                declination: 0, declinationVariation: 0, planarAngle: 0, planarAngleVariation: 0,
                initialColor: SIMD4(repeating: 1), initialRadius: 1, radiusVariation: 0,
                lifeSpan: 2, lifeSpanVariation: 0, shape: .sphere(radius: 1)
            )],
            modifiers: modifiers,
            subtextureOffsets: [],
            shaderPropertyRef: -1,
            alphaPropertyRef: -1,
            effectShader: nil,
            alphaProperty: nil,
            controllers: ParticleControllerSet()
        )
    }
}
