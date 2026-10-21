// The parameters of the gravity, drag, rotation, spawn, sub-texture, and
// inherit velocity modifiers. Positions and axes are in the particle system's
// own space. Semantics and their sources: docs/formats/nif-particles.md.

import Foundation
import simd

/// `NiPSysGravityModifier`: a pull along an axis, or towards a point.
nonisolated public struct ParticleGravity: Equatable, Sendable {
    /// nif.xml `ForceType`.
    public enum Force: UInt32, Equatable, Sendable {
        case planar = 0
        case spherical = 1
    }

    /// The gravity object's origin.
    public var position: SIMD3<Float>
    /// Unit length. With `worldAligned`, the axis is in world space.
    public var axis: SIMD3<Float>
    public var decay: Float
    /// Units per second the pull adds to a particle's speed each second.
    public var strength: Float
    public var force: Force
    /// Random push, units per second squared, times `turbulenceScale`.
    public var turbulence: Float
    public var turbulenceScale: Float
    public var worldAligned: Bool

    public init(
        position: SIMD3<Float>, axis: SIMD3<Float>, decay: Float, strength: Float, force: Force,
        turbulence: Float = 0, turbulenceScale: Float = 1, worldAligned: Bool = false
    ) {
        self.position = position
        self.axis = simd_length_squared(axis) > 0 ? simd_normalize(axis) : .zero
        self.decay = decay
        self.strength = strength
        self.force = force
        self.turbulence = turbulence
        self.turbulenceScale = turbulenceScale
        self.worldAligned = worldAligned
    }

    /// The gravity with `transform` applied. A world aligned axis does not turn.
    public func transformed(by transform: float4x4) -> ParticleGravity {
        var moved = self
        let point = transform * SIMD4(position, 1)
        moved.position = SIMD3(point.x, point.y, point.z)
        if !worldAligned {
            let turned = transform * SIMD4(axis, 0)
            let direction = SIMD3(turned.x, turned.y, turned.z)
            moved.axis = simd_length_squared(direction) > 0 ? simd_normalize(direction) : .zero
        }
        return moved
    }

    /// The change in velocity per second at `point`, without turbulence. A
    /// spherical pull points at the object and fades by `exp(-decay * distance)`.
    public func acceleration(at point: SIMD3<Float>) -> SIMD3<Float> {
        switch force {
        case .planar:
            return axis * strength
        case .spherical:
            let offset = position - point
            let distance = simd_length(offset)
            guard distance > 1e-6 else { return .zero }
            let fade = decay > 0 ? exp(-decay * distance) : 1
            return offset / distance * strength * fade
        }
    }
}

/// `NiPSysDragModifier`: slows particles near the drag object.
nonisolated public struct ParticleDrag: Equatable, Sendable {
    public var position: SIMD3<Float>
    /// Unit length; the range is measured along it.
    public var axis: SIMD3<Float>
    /// The share of the speed lost each thirtieth of a second.
    public var percentage: Float
    /// Full drag within this distance of the object.
    public var range: Float
    /// Drag fades to none over this distance past `range`.
    public var rangeFalloff: Float

    public init(
        position: SIMD3<Float>, axis: SIMD3<Float>, percentage: Float, range: Float,
        rangeFalloff: Float
    ) {
        self.position = position
        self.axis = simd_length_squared(axis) > 0 ? simd_normalize(axis) : .zero
        self.percentage = percentage
        self.range = range
        self.rangeFalloff = rangeFalloff
    }

    public func transformed(by transform: float4x4) -> ParticleDrag {
        var moved = self
        let point = transform * SIMD4(position, 1)
        let turned = transform * SIMD4(axis, 0)
        moved.position = SIMD3(point.x, point.y, point.z)
        let direction = SIMD3(turned.x, turned.y, turned.z)
        moved.axis = simd_length_squared(direction) > 0 ? simd_normalize(direction) : .zero
        return moved
    }

    /// The factor a particle's velocity keeps after `deltaTime` seconds at `point`.
    public func retained(at point: SIMD3<Float>, deltaTime: Float) -> Float {
        let distance = simd_length_squared(axis) > 0
            ? abs(simd_dot(point - position, axis)) : simd_distance(point, position)
        let past = distance - range
        let strength: Float = past <= 0 ? 1 : rangeFalloff > 0 ? max(0, 1 - past / rangeFalloff) : 0
        let loss = simd_clamp(percentage * strength, 0, 1)
        return pow(1 - loss, deltaTime * 30)
    }
}

/// `NiPSysRotationModifier`: each particle starts at a random angle and spins.
nonisolated public struct ParticleRotation: Equatable, Sendable {
    /// Radians per second.
    public var speed: Float
    public var speedVariation: Float
    public var angle: Float
    public var angleVariation: Float
    /// Half the particles spin the other way.
    public var randomSpeedSign: Bool
    public var randomAxis: Bool
    public var axis: SIMD3<Float>

    public init(
        speed: Float, speedVariation: Float, angle: Float, angleVariation: Float,
        randomSpeedSign: Bool, randomAxis: Bool, axis: SIMD3<Float>
    ) {
        self.speed = speed
        self.speedVariation = speedVariation
        self.angle = angle
        self.angleVariation = angleVariation
        self.randomSpeedSign = randomSpeedSign
        self.randomAxis = randomAxis
        self.axis = axis
    }
}

/// `NiPSysSpawnModifier`: new particles born from one that dies or collides.
nonisolated public struct ParticleSpawn: Equatable, Sendable {
    /// How many times a line of particles spawns again; 0 spawns once.
    public var generations: UInt16
    /// The chance, 0 to 1, that a dying particle spawns at all.
    public var percentage: Float
    public var minimumCount: UInt16
    public var maximumCount: UInt16
    /// The share of the parent's speed a child may gain or lose.
    public var speedVariation: Float
    /// Radians a child's direction may turn from the parent's.
    public var directionVariation: Float
    public var lifeSpan: Float
    public var lifeSpanVariation: Float

    public init(
        generations: UInt16, percentage: Float, minimumCount: UInt16, maximumCount: UInt16,
        speedVariation: Float, directionVariation: Float, lifeSpan: Float, lifeSpanVariation: Float
    ) {
        self.generations = generations
        self.percentage = percentage
        self.minimumCount = minimumCount
        self.maximumCount = maximumCount
        self.speedVariation = speedVariation
        self.directionVariation = directionVariation
        self.lifeSpan = lifeSpan
        self.lifeSpanVariation = lifeSpanVariation
    }
}

/// `BSPSysSubTexModifier`: each particle plays through the sub-texture frames.
nonisolated public struct ParticleSubTexture: Equatable, Sendable {
    public var startFrame: Float
    /// The first frame is `startFrame` plus up to this many frames, at random.
    public var startFrameFudge: Float
    public var endFrame: Float
    /// Past `endFrame`, playback goes back to here.
    public var loopStartFrame: Float
    public var loopStartFrameFudge: Float
    /// Frames played over the particle's life.
    public var frameCount: Float
    public var frameCountFudge: Float

    public init(
        startFrame: Float, startFrameFudge: Float, endFrame: Float, loopStartFrame: Float,
        loopStartFrameFudge: Float, frameCount: Float, frameCountFudge: Float
    ) {
        self.startFrame = startFrame
        self.startFrameFudge = startFrameFudge
        self.endFrame = endFrame
        self.loopStartFrame = loopStartFrame
        self.loopStartFrameFudge = loopStartFrameFudge
        self.frameCount = frameCount
        self.frameCountFudge = frameCountFudge
    }

    /// The frame at `fraction` of the life, for a particle that drew `start`,
    /// `loopStart`, and `frames`. The result stays inside `0 ..< frameTotal`.
    public func frame(
        at fraction: Float,
        start: Float,
        loopStart: Float,
        frames: Float,
        frameTotal: Int
    ) -> Int {
        guard frameTotal > 0 else { return 0 }
        let last = min(endFrame, Float(frameTotal - 1))
        var frame = start + simd_clamp(fraction, 0, 1) * max(frames, 0)
        if frame >= last + 1 {
            let span = max(last + 1 - loopStart, 1)
            frame = loopStart + (frame - last - 1).truncatingRemainder(dividingBy: span)
        }
        return Int(simd_clamp(frame.rounded(.down), 0, Float(frameTotal - 1)))
    }
}

/// `BSPSysInheritVelocityModifier`: a new particle takes some of its object's velocity.
nonisolated public struct ParticleInheritVelocity: Equatable, Sendable {
    /// Percent, 0 to 100.
    public var chance: Float
    public var multiplier: Float
    public var variation: Float

    public init(chance: Float, multiplier: Float, variation: Float) {
        self.chance = chance
        self.multiplier = multiplier
        self.variation = variation
    }
}
