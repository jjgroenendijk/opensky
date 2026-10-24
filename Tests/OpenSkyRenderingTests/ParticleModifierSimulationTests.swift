// The particle simulation with the gravity, drag, rotation, sub-texture, inherit
// velocity, and spawn modifiers, on engine values.

@testable import OpenSkyFormatsMesh
@testable import OpenSkyRenderCore
@testable import OpenSkyRendering
import simd
import Testing

struct ParticleModifierSimulationTests {
    @Test func gravityPullsAndDragSlows() {
        let gravity = ParticleGravity(
            position: .zero, axis: SIMD3(0, 0, -1), decay: 0, strength: 10, force: .planar
        )
        let drag = ParticleDrag(
            position: .zero, axis: .zero, percentage: 0.5, range: .greatestFiniteMagnitude,
            rangeFalloff: 0
        )
        let field = ParticleForceField(
            modifiers: [modifier(.gravity(gravity)), modifier(.drag(drag))],
            modelTransform: matrix_identity_float4x4
        )
        var random = ParticleRandom(seed: 1)
        var particle = SimulatedParticle(
            position: .zero, velocity: SIMD3(10, 0, 0), initialColor: SIMD4(repeating: 1),
            color: SIMD4(repeating: 1), initialRadius: 1, radius: 1, age: 0, lifetime: 1,
            atlasIndex: 0
        )
        #expect(field.move(&particle, deltaTime: 1 / 30, random: &random))
        #expect(simd_distance(particle.velocity, SIMD3(5, 0, -1 / 6)) < 1e-4)
    }

    @Test func rotationTurnsEachBillboardFromItsStartAngle() {
        let rotation = ParticleRotation(
            speed: 2, speedVariation: 0, angle: 0.5, angleVariation: 0, randomSpeedSign: false,
            randomAxis: true, axis: SIMD3(1, 0, 0)
        )
        var simulator = simulator(modifiers: [modifier(.rotation(rotation))])
        for _ in 0 ..< 10 {
            simulator.advance(deltaTime: 0.1, wind: .calm, emissionScale: 1)
        }
        #expect(!simulator.particles.isEmpty)
        for particle in simulator.particles {
            #expect(abs(particle.rotation - (0.5 + 2 * particle.age)) < 1e-4)
        }
    }

    @Test func subTexturePlaysTheFramesOverTheLife() {
        let subTexture = ParticleSubTexture(
            startFrame: 0, startFrameFudge: 0, endFrame: 3, loopStartFrame: 0,
            loopStartFrameFudge: 0, frameCount: 4, frameCountFudge: 0
        )
        var simulator = simulator(
            modifiers: [modifier(.subTex(subTexture))],
            subtextureOffsets: Array(repeating: SIMD4(0, 0, 0.5, 0.5), count: 4)
        )
        for _ in 0 ..< 30 {
            simulator.advance(deltaTime: 0.05, wind: .calm, emissionScale: 1)
        }
        let frames = Set(simulator.particles.map(\.atlasIndex))
        #expect(frames.isSuperset(of: [0, 1]))
        for particle in simulator.particles {
            let expected = min(Int((particle.age / particle.lifetime * 4).rounded(.down)), 3)
            #expect(abs(particle.atlasIndex - expected) <= 1)
        }
    }

    @Test func aMovingEmitterGivesNewParticlesItsVelocity() {
        let inherit = ParticleInheritVelocity(chance: 100, multiplier: 1, variation: 0)
        var simulator = simulator(modifiers: [modifier(.inheritVelocity(inherit))], speed: 0)
        var moved = matrix_identity_float4x4
        for step in 1 ... 10 {
            moved.columns.3 = SIMD4(Float(step), 0, 0, 1)
            simulator.move(to: moved)
            simulator.advance(deltaTime: 0.1, wind: .calm, emissionScale: 1)
        }
        #expect(!simulator.particles.isEmpty)
        for particle in simulator.particles {
            #expect(simd_distance(particle.velocity, SIMD3(10, 0, 0)) < 1e-4)
        }
    }

    @Test func aDyingParticleSpawnsOneGenerationOfChildren() {
        let spawn = ParticleSpawn(
            generations: 0, percentage: 1, minimumCount: 1, maximumCount: 1, speedVariation: 0,
            directionVariation: 0, lifeSpan: 5, lifeSpanVariation: 0
        )
        var simulator = simulator(modifiers: [modifier(.ageDeath(spawn: spawn))], lifeSpan: 0.1)
        for _ in 0 ..< 10 {
            simulator.advance(deltaTime: 0.05, wind: .calm, emissionScale: 1)
        }
        let children = simulator.particles.filter { $0.generation == 1 }
        #expect(!children.isEmpty)
        #expect(children.allSatisfy { $0.lifetime == 5 })
        #expect(!simulator.particles.contains { $0.generation > 1 })
    }

    private func modifier(_ kind: ParticleModifier.Kind) -> ParticleModifier {
        ParticleModifier(name: nil, order: 0, active: true, kind: kind)
    }

    private func simulator(
        modifiers: [ParticleModifier],
        speed: Float = 10,
        lifeSpan: Float = 2,
        subtextureOffsets: [SIMD4<Float>] = []
    ) -> ParticleSimulator {
        let definition = ParticleSystemDefinition(
            name: "Synthetic sparks",
            worldTransform: matrix_identity_float4x4,
            worldSpace: true,
            maxParticles: 64,
            emitters: [ParticleEmitter(
                name: "Sparks", order: 0, active: true, speed: speed, speedVariation: 0,
                declination: 0, declinationVariation: 0, planarAngle: 0, planarAngleVariation: 0,
                initialColor: SIMD4(repeating: 1), initialRadius: 1, radiusVariation: 0,
                lifeSpan: lifeSpan, lifeSpanVariation: 0, shape: .sphere(radius: 1)
            )],
            modifiers: modifiers,
            subtextureOffsets: subtextureOffsets,
            shaderPropertyRef: -1,
            alphaPropertyRef: -1,
            effectShader: nil,
            alphaProperty: nil,
            controllers: ParticleControllerSet()
        )
        return ParticleSimulator(
            definition: definition, placementTransform: matrix_identity_float4x4, seed: 7
        )
    }
}
