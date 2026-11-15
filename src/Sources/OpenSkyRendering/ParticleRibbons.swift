// Ribbon particle shapes: a camera-facing band between two points. A strip particle
// system joins its particles in birth order, and rain stretches each drop along its fall.
// See docs/rendering/particles.md#ribbons.

import OpenSkyFormatsCore
import simd

/// One band of a ribbon, in world space. `along` is the texture coordinate at each end.
nonisolated struct RibbonSegment: Equatable, Sendable {
    var start: SIMD3<Float>
    var end: SIMD3<Float>
    var startWidth: Float
    var endWidth: Float
    var color: SIMD4<Float>
    var along: SIMD2<Float>

    /// Packed into the billboard layout; the ribbon vertex shader reads it back.
    func instance(alongTextureV: Bool) -> ParticleGPUInstance {
        ParticleGPUInstance(
            positionSize: SIMD4(start, startWidth), color: color,
            uvRect: SIMD4(along.x, along.y, alongTextureV ? 1 : 0, 0),
            rotation: SIMD4(end, endWidth)
        )
    }
}

nonisolated enum ParticleRibbons {
    /// A strip system's particles in birth order, oldest first, joined into one band. The
    /// texture runs from the oldest end (0) to the newest (1).
    static func strip(_ particles: [SimulatedParticle]) -> [RibbonSegment] {
        let ordered = particles.sorted { $0.age > $1.age }
        guard ordered.count > 1 else { return [] }
        let last = Float(ordered.count - 1)
        return (0 ..< ordered.count - 1).map { index in
            let from = ordered[index]
            let to = ordered[index + 1]
            return RibbonSegment(
                start: from.position, end: to.position,
                startWidth: from.radius * 2, endWidth: to.radius * 2,
                color: (from.color + to.color) * 0.5,
                along: SIMD2(Float(index) / last, Float(index + 1) / last)
            )
        }
    }

    /// Each drop as a streak along its velocity. `aspect` is length over width; the area
    /// stays that of the square billboard.
    static func streaks(_ particles: [SimulatedParticle], aspect: Float) -> [RibbonSegment] {
        let ratio = max(aspect, 1).squareRoot()
        return particles.compactMap { particle in
            let speed = simd_length(particle.velocity)
            guard speed > 1e-4 else { return nil }
            let direction = particle.velocity / speed
            let half = particle.radius * ratio
            let width = particle.radius * 2 / ratio
            return RibbonSegment(
                start: particle.position - direction * half,
                end: particle.position + direction * half,
                startWidth: width, endWidth: width, color: particle.color, along: SIMD2(0, 1)
            )
        }
    }
}
