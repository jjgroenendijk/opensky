// Particle modifiers that push, stop, or wrap particles: the bomb force, the
// planar and spherical colliders, and the recycle bound. Positions and axes are
// in the particle system's own space. Semantics: docs/formats/nif-particles.md.

import Foundation
import simd

/// `NiPSysBombModifier`: a push away from (or, with a negative `deltaV`, towards)
/// the bomb object.
nonisolated public struct ParticleBomb: Equatable, Sendable {
    /// nif.xml `DecayType`.
    public enum Decay: UInt32, Equatable, Sendable {
        case none = 0
        case linear = 1
        case exponential = 2
    }

    /// nif.xml `SymmetryType`.
    public enum Symmetry: UInt32, Equatable, Sendable {
        case spherical = 0
        case cylindrical = 1
        case planar = 2
    }

    public let position: SIMD3<Float>
    /// Unit length, or zero when the file stores none.
    public let axis: SIMD3<Float>
    /// The distance over which the push fades.
    public let decay: Float
    /// Units per second the push adds to a particle's speed each second.
    public let deltaV: Float
    public let decayType: Decay
    public let symmetry: Symmetry

    public init(
        position: SIMD3<Float>, axis: SIMD3<Float>, decay: Float, deltaV: Float,
        decayType: Decay, symmetry: Symmetry
    ) {
        self.position = position
        self.axis = simd_length_squared(axis) > 0 ? simd_normalize(axis) : .zero
        self.decay = decay
        self.deltaV = deltaV
        self.decayType = decayType
        self.symmetry = symmetry
    }

    /// The bomb with `transform` applied, for a system placed in the world.
    public func transformed(by transform: float4x4) -> ParticleBomb {
        let moved = transform * SIMD4(position, 1)
        let turned = transform * SIMD4(axis, 0)
        return ParticleBomb(
            position: SIMD3(moved.x, moved.y, moved.z), axis: SIMD3(turned.x, turned.y, turned.z),
            decay: decay, deltaV: deltaV, decayType: decayType, symmetry: symmetry
        )
    }

    /// The change in velocity per second for a particle at `point`.
    public func acceleration(at point: SIMD3<Float>) -> SIMD3<Float> {
        let offset = point - position
        let direction: SIMD3<Float> = switch symmetry {
        case .spherical: offset
        case .cylindrical: offset - axis * simd_dot(offset, axis)
        case .planar: axis * (simd_dot(offset, axis) < 0 ? -1 : 1)
        }
        let distance = symmetry == .planar ? abs(simd_dot(offset, axis)) : simd_length(direction)
        guard simd_length_squared(direction) > 1e-12 else { return .zero }
        return simd_normalize(direction) * deltaV * falloff(distance)
    }

    private func falloff(_ distance: Float) -> Float {
        guard decay > 0 else { return decayType == .none ? 1 : 0 }
        return switch decayType {
        case .none: 1
        case .linear: max(0, 1 - distance / decay)
        case .exponential: exp(-distance / decay)
        }
    }
}

/// One `NiPSysPlanarCollider` or `NiPSysSphericalCollider`.
nonisolated public struct ParticleCollider: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        /// A rectangle: its centre, and its two half axes along its sides.
        case plane(center: SIMD3<Float>, halfX: SIMD3<Float>, halfY: SIMD3<Float>)
        case sphere(center: SIMD3<Float>, radius: Float)
    }

    /// The share of the speed into the surface that a particle keeps, turned back.
    public let bounce: Float
    public let diesOnCollide: Bool
    public let shape: Shape

    public init(bounce: Float, diesOnCollide: Bool, shape: Shape) {
        self.bounce = bounce
        self.diesOnCollide = diesOnCollide
        self.shape = shape
    }

    /// The collider with `transform` applied, for a system placed in the world.
    public func transformed(by transform: float4x4) -> ParticleCollider {
        func point(_ value: SIMD3<Float>) -> SIMD3<Float> {
            let moved = transform * SIMD4(value, 1)
            return SIMD3(moved.x, moved.y, moved.z)
        }
        func vector(_ value: SIMD3<Float>) -> SIMD3<Float> {
            let moved = transform * SIMD4(value, 0)
            return SIMD3(moved.x, moved.y, moved.z)
        }
        return switch shape {
        case let .plane(center, halfX, halfY):
            ParticleCollider(
                bounce: bounce, diesOnCollide: diesOnCollide,
                shape: .plane(center: point(center), halfX: vector(halfX), halfY: vector(halfY))
            )
        case let .sphere(center, radius):
            ParticleCollider(
                bounce: bounce, diesOnCollide: diesOnCollide,
                shape: .sphere(
                    center: point(center),
                    radius: radius * simd_length(vector([1, 0, 0]))
                )
            )
        }
    }

    /// What happens to a particle that moves from `start` to `end` this step.
    public enum Hit: Equatable, Sendable {
        case none
        case dies
        /// The particle stops at `position` with the bounced `velocity`.
        case bounces(position: SIMD3<Float>, velocity: SIMD3<Float>)
    }

    public func hit(from start: SIMD3<Float>, to end: SIMD3<Float>, velocity: SIMD3<Float>) -> Hit {
        guard let contact = contact(from: start, to: end) else { return .none }
        if diesOnCollide {
            return .dies
        }
        let inward = simd_dot(velocity, contact.normal)
        let bounced = velocity - contact.normal * inward * (1 + bounce)
        return .bounces(position: contact.position, velocity: bounced)
    }

    /// Where the step first crosses the surface, and the normal facing the start.
    private func contact(
        from start: SIMD3<Float>, to end: SIMD3<Float>
    ) -> (position: SIMD3<Float>, normal: SIMD3<Float>)? {
        switch shape {
        case let .plane(center, halfX, halfY):
            let normal = simd_cross(halfX, halfY)
            guard simd_length_squared(normal) > 1e-12 else { return nil }
            let unit = simd_normalize(normal)
            let before = simd_dot(start - center, unit)
            let after = simd_dot(end - center, unit)
            guard before * after < 0 || (before != 0 && after == 0) else { return nil }
            let point = start + (end - start) * (before / (before - after))
            let local = point - center
            guard
                abs(simd_dot(local, halfX)) <= simd_length_squared(halfX),
                abs(simd_dot(local, halfY)) <= simd_length_squared(halfY)
            else { return nil }
            return (point, before > 0 ? unit : -unit)
        case let .sphere(center, radius):
            let wasOutside = simd_distance(start, center) >= radius
            guard wasOutside, simd_distance(end, center) < radius else { return nil }
            let normal = simd_normalize(start - center)
            return (center + normal * radius, normal)
        }
    }
}

/// `BSPSysRecycleBoundModifier`: particles that leave the box come back in on the
/// other side, so a camera-attached system keeps the view filled. The box is axis
/// aligned in the system's space.
nonisolated public struct ParticleRecycleBound: Equatable, Sendable {
    /// The box's lowest corner: the bound object's position plus the offset.
    public let minimum: SIMD3<Float>
    /// The box's size on each axis; zero turns the wrap off on that axis.
    public let size: SIMD3<Float>

    public init(minimum: SIMD3<Float>, size: SIMD3<Float>) {
        self.minimum = minimum
        self.size = size
    }

    /// `point` moved back into the box by whole box sizes.
    public func wrapped(_ point: SIMD3<Float>) -> SIMD3<Float> {
        var result = point
        for axis in 0 ..< 3 where size[axis] > 0 {
            let offset = result[axis] - minimum[axis]
            result[axis] = minimum[axis] + offset - (offset / size[axis])
                .rounded(.down) * size[axis]
        }
        return result
    }
}
