// The modifiers that push, slow, stop, or wrap a particle as it moves: bombs,
// gravity, drag, and colliders placed in the world for one step, and recycle
// bounds kept in the system's own space. Semantics: docs/formats/nif-particles.md.

import OpenSkyFormatsMesh
import simd

nonisolated struct ParticleForceField {
    private var bombs: [ParticleBomb] = []
    private var gravities: [ParticleGravity] = []
    private var drags: [ParticleDrag] = []
    private var colliders: [ParticleCollider] = []
    private var recycleBounds: [ParticleRecycleBound] = []
    private let toSystem: float4x4
    private let toWorld: float4x4

    /// `modifiers` are the active ones; `modelTransform` takes system space to the world.
    init(modifiers: [ParticleModifier], modelTransform: float4x4) {
        toWorld = modelTransform
        toSystem = modelTransform.inverse
        for modifier in modifiers {
            switch modifier.kind {
            case let .bomb(bomb): bombs.append(bomb.transformed(by: modelTransform))
            case let .gravity(gravity): gravities.append(gravity.transformed(by: modelTransform))
            case let .drag(drag): drags.append(drag.transformed(by: modelTransform))
            case let .colliders(list): colliders += list.map { $0.transformed(by: modelTransform) }
            case let .recycleBound(bound): recycleBounds.append(bound)
            default: break
            }
        }
    }

    /// Steps `particle` by its velocity. False when a collider kills it.
    func move(
        _ particle: inout SimulatedParticle,
        deltaTime: Float,
        random: inout ParticleRandom
    ) -> Bool {
        for bomb in bombs {
            particle.velocity += bomb.acceleration(at: particle.position) * deltaTime
        }
        for gravity in gravities {
            particle.velocity += gravity.acceleration(at: particle.position) * deltaTime
            guard gravity.turbulence > 0 else { continue }
            let push = SIMD3(random.signed(), random.signed(), random.signed())
            particle.velocity += push * gravity.turbulence * gravity.turbulenceScale * deltaTime
        }
        for drag in drags {
            particle.velocity *= drag.retained(at: particle.position, deltaTime: deltaTime)
        }
        let start = particle.position
        var end = start + particle.velocity * deltaTime
        for collider in colliders {
            switch collider.hit(from: start, to: end, velocity: particle.velocity) {
            case .none: continue
            case .dies: return false
            case let .bounces(position, velocity):
                particle.velocity = velocity
                end = position
            }
        }
        particle.position = recycleBounds.isEmpty ? end : wrapped(end)
        return true
    }

    private func wrapped(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let local4 = toSystem * SIMD4(point, 1)
        var local = SIMD3(local4.x, local4.y, local4.z)
        for bound in recycleBounds {
            local = bound.wrapped(local)
        }
        let world = toWorld * SIMD4(local, 1)
        return SIMD3(world.x, world.y, world.z)
    }
}
