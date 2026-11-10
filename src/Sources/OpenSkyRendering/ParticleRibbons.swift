// Ribbon particle shapes: a camera-facing band between two points. A strip particle
// system joins its particles in birth order, rain stretches each drop along its fall, and a
// lightning controller grows a bent bolt. See docs/rendering/particles.md#ribbons.

import OpenSkyFormatsCore
public import OpenSkyFormatsMesh
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

/// A lightning bolt from its controller's fields. Each period grows a new bolt from a new
/// seed, and the bolt blends from one to the next, so it crawls rather than jumps.
nonisolated public struct LightningBolt: Sendable {
    /// Seconds between two grown bolts; OpenSky's choice.
    static let period: Float = 0.1
    /// Segments of every branch together, at most.
    public static let segmentCapacity = 1024

    public let parameters: ParticleLightning
    public let seed: UInt64

    public init(parameters: ParticleLightning, seed: UInt64) {
        self.parameters = parameters
        self.seed = seed
    }

    /// The bolt at `time` in the shape's own space, along +Y.
    func segments(at time: Float, color: SIMD4<Float>) -> [RibbonSegment] {
        let step = max(time, 0) / Self.period
        let index = UInt64(step.rounded(.down))
        let blend = step - step.rounded(.down)
        let from = branches(generation: index)
        let to = branches(generation: index + 1)
        var result: [RibbonSegment] = []
        for (first, second) in zip(from, to) where first.points.count == second.points.count {
            let points = zip(first.points, second.points).map { pair in
                simd_mix(pair.0, pair.1, SIMD3(repeating: blend))
            }
            result += Self.band(
                points, width: first.width, fades: first.fades, color: color
            )
            if result.count >= Self.segmentCapacity {
                break
            }
        }
        return Array(result.prefix(Self.segmentCapacity))
    }

    struct Branch {
        var points: [SIMD3<Float>]
        var width: Float
        var fades: Bool
    }

    /// The main bolt, then its branches. One generation always draws the same random
    /// numbers in the same order, so the blend pairs matching points.
    func branches(generation: UInt64) -> [Branch] {
        var random = SplitMix64(seed: seed &+ generation &* 0x9E37_79B9_7F4A_7C15)
        let levels = min(parameters.subdivisions, 8)
        let length = max(parameters.length + signed(&random) * parameters.lengthVariation, 0)
        let main = bend(
            from: .zero, to: SIMD3(0, length, 0), levels: levels,
            amplitude: parameters.arcOffset, random: &random
        )
        var result = [Branch(
            points: main,
            width: parameters.width,
            fades: parameters.fadesMainBolt
        )]
        let spread = parameters.branchVariation
        let count = max(parameters.branches + Int((signed(&random) * Float(spread)).rounded()), 0)
        for _ in 0 ..< count {
            let startIndex = min(
                Int(Float(main.count - 1) * (0.1 + unit(&random) * 0.7)),
                main.count - 1
            )
            let start = main[startIndex]
            let sideways = SIMD3(signed(&random), 0, signed(&random))
            let direction = simd_normalize(SIMD3<Float>(0, 1, 0) + sideways * 0.6)
            let reach = length * (0.3 + unit(&random) * 0.2)
            let points = bend(
                from: start, to: start + direction * reach, levels: max(levels - 2, 1),
                amplitude: parameters.arcOffset * 0.5, random: &random
            )
            result.append(Branch(
                points: points, width: parameters.width * parameters.childWidthMultiplier,
                fades: parameters.fadesChildBolts
            ))
        }
        return result
    }

    /// Midpoint displacement: each level halves every piece and pushes the new point
    /// sideways, by half as much as the level before.
    private func bend(
        from start: SIMD3<Float>, to end: SIMD3<Float>, levels: Int, amplitude: Float,
        random: inout SplitMix64
    ) -> [SIMD3<Float>] {
        var points = [start, end]
        var reach = amplitude
        for _ in 0 ..< levels {
            var next: [SIMD3<Float>] = [points[0]]
            for index in 1 ..< points.count {
                let middle = (points[index - 1] + points[index]) * 0.5
                let push = SIMD3(signed(&random), 0, signed(&random)) * reach
                next += [middle + push, points[index]]
            }
            points = next
            reach *= 0.5
        }
        return points
    }

    private static func band(
        _ points: [SIMD3<Float>], width: Float, fades: Bool, color: SIMD4<Float>
    ) -> [RibbonSegment] {
        guard points.count > 1 else { return [] }
        let last = Float(points.count - 1)
        return (0 ..< points.count - 1).map { index in
            let along = SIMD2(Float(index), Float(index + 1)) / last
            let taper = fades ? 1 - along : SIMD2(repeating: 1)
            var shaded = color
            shaded.w *= fades ? 1 - (along.x + along.y) * 0.5 : 1
            return RibbonSegment(
                start: points[index], end: points[index + 1],
                startWidth: width * taper.x, endWidth: width * taper.y,
                color: shaded, along: along
            )
        }
    }

    private func unit(_ random: inout SplitMix64) -> Float {
        Float(random.next() >> 40) / Float(1 << 24)
    }

    private func signed(_ random: inout SplitMix64) -> Float {
        unit(&random) * 2 - 1
    }
}
