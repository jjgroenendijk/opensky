// Particle birth: where and how a new particle starts, and the children a dying
// particle spawns. Modifier semantics and what OpenSky infers:
// docs/formats/nif-particles.md#parameter-modifiers.

import OpenSkyFormatsMesh
import simd

nonisolated extension ParticleSimulator {
    mutating func makeParticle(emitter: ParticleEmitter) -> SimulatedParticle {
        let modelTransform = placementTransform * definition.worldTransform
        let birth = sampleBirth(shape: emitter.shape)
        let worldPosition4 = modelTransform * SIMD4(birth.position, 1)
        let declination = emitter.declination + random.signed() * emitter.declinationVariation
        let planar = emitter.planarAngle + random.signed() * emitter.planarAngleVariation
        let localDirection = birth.direction ?? SIMD3(
            sin(declination) * cos(planar),
            sin(declination) * sin(planar),
            cos(declination)
        )
        let worldVelocity4 = modelTransform * SIMD4(localDirection, 0)
        let transformedDirection = SIMD3(
            worldVelocity4.x, worldVelocity4.y, worldVelocity4.z
        )
        let directionLength = simd_length(transformedDirection)
        let direction = directionLength > .ulpOfOne
            ? transformedDirection / directionLength : SIMD3<Float>(0, 0, 1)
        let speed = max(emitter.speed + random.signed() * emitter.speedVariation, 0)
            * spawnScale.speed
        let lifetime = max(emitter.lifeSpan + random.signed() * emitter.lifeSpanVariation, 0.01)
            / spawnScale.speed
        let radius = max(emitter.initialRadius + random.signed() * emitter.radiusVariation, 0.01)
            * spawnScale.size
        let atlasCount = max(definition.subtextureOffsets.count, 1)
        let initialRampColour = colourRamp?.colour(at: 0) ?? SIMD4(repeating: 1)
        var particle = SimulatedParticle(
            position: SIMD3(worldPosition4.x, worldPosition4.y, worldPosition4.z),
            velocity: direction * speed,
            initialColor: emitter.initialColor,
            color: emitter.initialColor * initialRampColour,
            initialRadius: radius,
            radius: radius,
            age: 0,
            lifetime: lifetime,
            atlasIndex: min(Int(random.unit() * Float(atlasCount)), atlasCount - 1)
        )
        applyBirthModifiers(to: &particle)
        return particle
    }

    /// Birth position in system space, and a start direction when the shape sets one.
    private mutating func sampleBirth(
        shape: ParticleEmitter.Shape
    ) -> (position: SIMD3<Float>, direction: SIMD3<Float>?) {
        guard case let .mesh(source) = shape else {
            return (samplePosition(shape: shape), nil)
        }
        let sampler = MeshEmitterSampler(source: source)
        let point = sampler.sample { random.unit() }
        let direction: SIMD3<Float>? = switch source.velocity {
        case .normals: point.normal
        case .direction: source.emissionAxis
        case .random: randomDirection()
        }
        return (point.position, direction)
    }

    private mutating func randomDirection() -> SIMD3<Float> {
        let z = random.signed()
        let angle = random.unit() * 2 * Float.pi
        let xy = sqrt(max(1 - z * z, 0))
        return SIMD3(xy * cos(angle), xy * sin(angle), z)
    }

    private mutating func samplePosition(shape: ParticleEmitter.Shape) -> SIMD3<Float> {
        switch shape {
        case let .box(width, height, depth):
            return SIMD3(random.signed() * width, random.signed() * height, random.signed() * depth)
                * 0.5
        case let .cylinder(radius, height):
            let angle = random.unit() * 2 * Float.pi
            let distance = sqrt(random.unit()) * radius
            return SIMD3(
                cos(angle) * distance,
                sin(angle) * distance,
                random.signed() * height * 0.5
            )
        case let .sphere(radius):
            let z = random.signed()
            let angle = random.unit() * 2 * Float.pi
            let radial = pow(random.unit(), 1 / 3 as Float) * radius
            let xy = sqrt(max(1 - z * z, 0))
            return SIMD3(xy * cos(angle), xy * sin(angle), z) * radial
        case .mesh:
            return .zero
        }
    }

    /// Sets the start values the rotation, sub-texture, and inherit velocity modifiers give.
    private mutating func applyBirthModifiers(to particle: inout SimulatedParticle) {
        for modifier in activeModifiers {
            switch modifier.kind {
            case let .rotation(rotation):
                particle.rotation = rotation.angle + random.signed() * rotation.angleVariation
                let speed = rotation.speed + random.signed() * rotation.speedVariation
                let flips = rotation.randomSpeedSign && random.unit() < 0.5
                particle.rotationSpeed = flips ? -speed : speed
            case let .subTex(subTexture):
                particle.frames = SIMD3(
                    subTexture.startFrame + random.unit() * subTexture.startFrameFudge,
                    subTexture.loopStartFrame + random.unit() * subTexture.loopStartFrameFudge,
                    subTexture.frameCount + random.unit() * subTexture.frameCountFudge
                )
                particle.atlasIndex = subTexture.frame(
                    at: 0, start: particle.frames.x, loopStart: particle.frames.y,
                    frames: particle.frames.z, frameTotal: definition.subtextureOffsets.count
                )
            case let .inheritVelocity(inherit):
                // A local-space system already carries its particles along.
                guard definition.worldSpace, random.unit() * 100 < inherit.chance else { continue }
                let share = inherit.multiplier + random.signed() * inherit.variation
                particle.velocity += emitterVelocity * share
            default:
                break
            }
        }
    }

    /// The spawn of the active age death modifier, nil when death spawns nothing.
    private var deathSpawn: ParticleSpawn? {
        for modifier in activeModifiers {
            if case let .ageDeath(spawn?) = modifier.kind {
                return spawn
            }
        }
        return nil
    }

    /// The children `parent` spawns as it dies. A particle spawns while its generation
    /// is at most the spawn's generation count, so a count of 0 spawns once.
    mutating func spawned(from parent: SimulatedParticle) -> [SimulatedParticle] {
        guard
            let spawn = deathSpawn, parent.generation <= spawn.generations,
            random.unit() < spawn.percentage
        else { return [] }
        let spread = Int(spawn.maximumCount - spawn.minimumCount)
        let count = Int(spawn.minimumCount) + min(Int(random.unit() * Float(spread + 1)), spread)
        return (0 ..< count).map { _ in child(of: parent, spawn: spawn) }
    }

    private mutating func child(
        of parent: SimulatedParticle,
        spawn: ParticleSpawn
    ) -> SimulatedParticle {
        var child = parent
        let speed = simd_length(parent.velocity)
        let direction = speed > .ulpOfOne ? parent.velocity / speed : randomDirection()
        let turned = direction + randomDirection() * sin(spawn.directionVariation) * random.unit()
        let length = simd_length(turned)
        child.velocity = (length > .ulpOfOne ? turned / length : direction)
            * speed * max(1 + random.signed() * spawn.speedVariation, 0)
        child.age = 0
        child.lifetime = max(spawn.lifeSpan + random.signed() * spawn.lifeSpanVariation, 0.01)
        child.color = parent.initialColor
        child.radius = parent.initialRadius
        child.generation = min(parent.generation, .max - 1) + 1
        return child
    }
}
