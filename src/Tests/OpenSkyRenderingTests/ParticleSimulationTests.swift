// The particle simulation's force field and update switch, on engine values.

@testable import OpenSkyFormatsMesh
@testable import OpenSkyRenderCore
@testable import OpenSkyRendering
import simd
import Testing

struct ParticleSimulationTests {
    /// A bomb pushes, a dying collider removes, and a recycle bound wraps.
    @Test func forceFieldPushesKillsAndWraps() {
        let bomb = ParticleBomb(
            position: .zero, axis: .zero, decay: 0, deltaV: 10, decayType: .none,
            symmetry: .spherical
        )
        let wall = ParticleCollider(
            bounce: 0, diesOnCollide: true,
            shape: .plane(center: SIMD3(0, 0, 5), halfX: SIMD3(10, 0, 0), halfY: SIMD3(0, 10, 0))
        )
        let bound = ParticleRecycleBound(minimum: SIMD3(-1, -1, -1), size: SIMD3(2, 2, 0))
        var lifted = matrix_identity_float4x4
        lifted.columns.3 = SIMD4(0, 0, 3, 1)
        let field = ParticleForceField(
            modifiers: [
                modifier(.bomb(bomb)),
                modifier(.colliders([wall])),
                modifier(.recycleBound(bound))
            ],
            modelTransform: lifted
        )
        var random = ParticleRandom(seed: 1)
        var pushed = particle(at: SIMD3(1.5, 0, 4), velocity: .zero)
        #expect(field.move(&pushed, deltaTime: 0.1, random: &random))
        #expect(pushed.velocity.z > 0)
        #expect(pushed.position.x < 1)
        var doomed = particle(at: SIMD3(0, 0, 7), velocity: SIMD3(0, 0, 100))
        #expect(!field.move(&doomed, deltaTime: 0.1, random: &random))
    }

    @Test func aSystemWithoutAnUpdateControllerStandsStill() {
        for updates in [true, false] {
            var simulator = ParticleSimulator(
                definition: definition(
                    controllers: ParticleControllerSet(updatesSimulation: updates)
                ),
                placementTransform: matrix_identity_float4x4,
                seed: 3
            )
            for _ in 0 ..< 10 {
                simulator.advance(deltaTime: 0.05, wind: .calm, emissionScale: 1)
            }
            #expect(simulator.particles.isEmpty == !updates)
        }
    }

    private func modifier(_ kind: ParticleModifier.Kind) -> ParticleModifier {
        ParticleModifier(name: nil, order: 0, active: true, kind: kind)
    }

    private func particle(at position: SIMD3<Float>, velocity: SIMD3<Float>) -> SimulatedParticle {
        SimulatedParticle(
            position: position, velocity: velocity, initialColor: SIMD4(repeating: 1),
            color: SIMD4(repeating: 1), initialRadius: 1, radius: 1, age: 0, lifetime: 1,
            atlasIndex: 0
        )
    }

    private func definition(
        modifiers: [ParticleModifier] = [],
        controllers: ParticleControllerSet = ParticleControllerSet()
    ) -> ParticleSystemDefinition {
        ParticleSystemDefinition(
            name: "Synthetic sparks",
            worldTransform: matrix_identity_float4x4,
            worldSpace: true,
            maxParticles: 16,
            emitters: [ParticleEmitter(
                name: "Sparks", order: 0, active: true, speed: 10, speedVariation: 0,
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
            controllers: controllers
        )
    }
}
