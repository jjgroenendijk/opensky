// The bolt tree a lightning controller grows, as two crossed flat ribbons per bolt, and
// the tracks that decide when a new one is grown. See docs/rendering/particles.md#lightning.

import OpenSkyFormatsCore
public import OpenSkyFormatsMesh
import simd

/// One flat piece of a bolt in the shape's own space. `side` is the direction its width
/// runs in, so the piece does not turn to the eye.
nonisolated struct LightningQuad: Equatable, Sendable {
    var start: SIMD3<Float>
    var end: SIMD3<Float>
    var side: SIMD3<Float>
    var width: Float
    /// The alpha at the start and at the end.
    var alpha: SIMD2<Float>
    /// The texture V at the start and at the end.
    var along: SIMD2<Float>

    /// Packed into the billboard layout; the ribbon vertex shader reads it back.
    func instance(model: float4x4) -> ParticleGPUInstance {
        let turned = model * SIMD4(side, 0)
        let reach = simd_length(turned)
        let direction = reach > 1e-6 ? simd_make_float3(turned) / reach : side
        return ParticleGPUInstance(
            positionSize: SIMD4(Self.point(model, start), width * reach),
            color: SIMD4(direction, alpha.x),
            uvRect: SIMD4(along.x, along.y, RibbonMode.fixedSide, alpha.y),
            rotation: SIMD4(Self.point(model, end), width * reach)
        )
    }

    private static func point(_ matrix: float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
        simd_make_float3(matrix * SIMD4(point, 1))
    }
}

/// What `uvRect.z` of a ribbon instance tells the vertex shader.
nonisolated enum RibbonMode {
    /// The band keeps its own side direction, held in the instance colour with an alpha.
    static let fixedSide: Float = 2
}

/// A lightning bolt from its controller's fields and tracks.
nonisolated public struct LightningBolt: Sendable {
    /// Quads of every bolt together, at most.
    public static let quadCapacity = 2048

    public let parameters: ParticleLightning
    public let seed: UInt64

    public init(parameters: ParticleLightning, seed: UInt64) {
        self.parameters = parameters
        self.seed = seed
    }

    /// One bolt of the tree: its points, from its start to its far end.
    struct Branch: Equatable {
        var points: [SIMD3<Float>]
        var width: Float
        var fades: Bool
        var isMain: Bool
    }

    /// Which sequence feeds the bolt, when it began, and what the bolt carried into it.
    struct Play: Equatable, Sendable {
        /// Lowercased; nil plays the default tracks.
        var sequence: String?
        /// The playback time the sequence began at.
        var start: Float = 0
        /// The bolt showed when the sequence began. A sequence that leaves the
        /// generation unset keeps that state.
        var held = false
        var generation: UInt64 = 0
        var mutation: UInt64 = 0
        /// The values the earlier sequence left; nil uses the controller's fields.
        var values: ParticleLightning?
    }

    /// Which bolt shows at one time: the values the tracks give, and the two counters
    /// that pick its random numbers.
    struct Moment: Equatable {
        var values: ParticleLightning
        /// Rises when the generation track changes: a new tree.
        var generation: UInt64
        /// Rises when the mutation track changes: the same tree, new lengths and bends.
        var mutation: UInt64
        var isOn: Bool
    }

    /// The quads at `seconds` of playback. Empty while the generation track is off, and
    /// for a controller no generation track feeds.
    func quads(at seconds: Float, play: Play = Play()) -> [LightningQuad] {
        guard let moment = moment(at: seconds, play: play), moment.isOn else { return [] }
        var quads: [LightningQuad] = []
        for branch in branches(moment) {
            quads += Self.quads(branch)
            if quads.count >= Self.quadCapacity {
                break
            }
        }
        return Array(quads.prefix(Self.quadCapacity))
    }

    /// Nil when no tracks feed the controller.
    func moment(at seconds: Float, play: Play = Play()) -> Moment? {
        let tracks = play.sequence.flatMap { parameters.sequenceTracks[$0] } ?? parameters.tracks
        guard let tracks else { return nil }
        let local = max(seconds - play.start, 0)
        let time = tracks.timing.controllerTime(at: local)
        var values = play.values ?? parameters
        values.apply(tracks, at: time)
        let count = { (keys: [NIFKey<Bool>]) in
            LightningTrackCount.changes(keys, timing: tracks.timing, seconds: local)
        }
        return Moment(
            values: values,
            generation: play.generation + count(tracks.generation),
            mutation: play.mutation + count(tracks.mutation),
            isOn: tracks.generation.isEmpty
                ? play.held : NIFKeySampler.step(tracks.generation, at: time) == true
        )
    }

    /// The play state after an effect graph asks for `name` at `seconds`. A sequence that
    /// does not feed the controller changes nothing; the same name again is a no-op.
    func play(_ current: Play, switchedTo name: String, at seconds: Float) -> Play {
        let key = name.lowercased()
        guard key != current.sequence, parameters.sequenceTracks[key] != nil else {
            return current
        }
        let before = moment(at: seconds, play: current)
        // A bolt that was off must not come back as the tree it was before.
        let wasOn = before?.isOn == true
        return Play(
            sequence: key, start: seconds, held: wasOn,
            generation: (before?.generation ?? current.generation) + (wasOn ? 0 : 1),
            mutation: before?.mutation ?? current.mutation,
            values: before?.values
        )
    }

    /// The most quads the stored fields can grow, for the size of the draw buffer.
    var maxQuads: Int {
        func count(_ subdivisions: Int, _ branches: Int, _ variation: Int) -> Int {
            let own = 2 << min(max(subdivisions, 0), 12)
            guard branches > 0, subdivisions > 0, own < Self.quadCapacity else { return own }
            let children = count(subdivisions - 1, branches / 2, variation / 2)
            return min(own + (branches + variation) * children, Self.quadCapacity)
        }
        return min(
            count(parameters.subdivisions, parameters.branches, parameters.branchVariation),
            Self.quadCapacity
        )
    }

    /// The main bolt first, then every child below it, parent before child.
    func branches(_ moment: Moment) -> [Branch] {
        let mixed = seed &+ moment.generation &* SplitMix64.increment
        var growth = Growth(
            tree: SplitMix64(seed: mixed),
            shape: SplitMix64(seed: mixed ^ (moment.mutation &+ 1) &* 0xD6E8_FEB8_6659_FD93),
            budget: Self.quadCapacity
        )
        grow(
            Level(
                depth: 0, subdivisions: moment.values.subdivisions,
                branches: moment.values.branches, variation: moment.values.branchVariation,
                origin: .zero
            ),
            values: moment.values, growth: &growth
        )
        return growth.branches
    }

    private struct Level {
        var depth: Int
        var subdivisions: Int
        var branches: Int
        var variation: Int
        var origin: SIMD3<Float>
    }

    /// What growing a tree carries along: `tree` draws where children start, `shape`
    /// draws the points, and `budget` is the quads left in the buffer.
    private struct Growth {
        var tree: SplitMix64
        var shape: SplitMix64
        var budget: Int
        var branches: [Branch] = []
    }

    /// Adds the bolt of `level`, then its children. A child is one step deeper: half the
    /// branch count and variation, and one subdivision less.
    private func grow(
        _ level: Level, values: ParticleLightning, growth: inout Growth
    ) {
        // A bolt too fine for the buffer is drawn with fewer segments.
        var segments = 1 << min(max(level.subdivisions, 0), 12)
        while segments > 1, segments * 2 > growth.budget {
            segments >>= 1
        }
        guard growth.budget >= segments * 2 else { return }
        growth.budget -= segments * 2
        let scale = Float(level.depth)
        let length = max(
            pow(0.5, scale) * values.length
                + pow(0.25, scale) * Self.signed(&growth.shape) * values.lengthVariation,
            0
        )
        let offsets = Self.displaced(
            segments: segments, size: pow(0.5, scale) * values.arcOffset, random: &growth.shape
        )
        let points = offsets.enumerated().map { index, offset in
            level.origin
                + SIMD3(offset.x, length * Float(index) / Float(segments), offset.y)
        }
        growth.branches.append(Branch(
            points: points,
            width: pow(values.childWidthMultiplier, scale) * values.width,
            fades: level.depth == 0 ? values.fadesMainBolt : values.fadesChildBolts,
            isMain: level.depth == 0
        ))
        guard level.branches > 0, level.subdivisions > 0 else { return }
        let spread = Self.signed(&growth.tree) * Float(level.variation)
        let count = max(level.branches + Int(spread.rounded()), 0)
        for _ in 0 ..< count {
            // The middle of a random segment in the parent's first half.
            let segment = Int(Self.unit(&growth.tree) * Float(max(segments / 2, 1)))
            let start = (points[segment] + points[segment + 1]) * 0.5
            grow(
                Level(
                    depth: level.depth + 1, subdivisions: level.subdivisions - 1,
                    branches: level.branches / 2, variation: level.variation / 2, origin: start
                ),
                values: values, growth: &growth
            )
        }
    }

    /// Midpoint displacement: the middle point moves sideways by `size` in a random
    /// direction, then each half does the same with half the size. Both ends stay at 0.
    static func displaced(
        segments: Int, size: Float, random: inout SplitMix64
    ) -> [SIMD2<Float>] {
        var offsets = [SIMD2<Float>](repeating: .zero, count: segments + 1)
        var spans = [(lower: 0, upper: segments, size: size)]
        while let span = spans.popLast() {
            guard span.upper - span.lower > 1 else { continue }
            let middle = (span.lower + span.upper) / 2
            let angle = unit(&random) * 2 * Float.pi
            offsets[middle] = (offsets[span.lower] + offsets[span.upper]) * 0.5
                + SIMD2(cos(angle), sin(angle)) * span.size
            spans.append((middle, span.upper, span.size * 0.5))
            spans.append((span.lower, middle, span.size * 0.5))
        }
        return offsets
    }

    /// Two crossed ribbons along the bolt, one wide in X and one wide in Z. The alpha is
    /// 0 at the far end and at the start of the main bolt; a fading bolt also loses
    /// alpha with the square of the way along it.
    static func quads(_ branch: Branch) -> [LightningQuad] {
        let count = branch.points.count - 1
        guard count > 0 else { return [] }
        let alpha = { (index: Int) -> Float in
            if index == count || (branch.isMain && index == 0) {
                return 0
            }
            let along = Float(index) / Float(count)
            return branch.fades ? 1 - along * along : 1
        }
        return (0 ..< count).flatMap { index in
            [SIMD3<Float>(1, 0, 0), SIMD3(0, 0, 1)].map { side in
                LightningQuad(
                    start: branch.points[index], end: branch.points[index + 1], side: side,
                    width: branch.width, alpha: SIMD2(alpha(index), alpha(index + 1)),
                    along: SIMD2(Float(index), Float(index + 1)) / Float(count)
                )
            }
        }
    }

    private static func unit(_ random: inout SplitMix64) -> Float {
        Float(random.next() >> 40) / Float(1 << 24)
    }

    private static func signed(_ random: inout SplitMix64) -> Float {
        unit(&random) * 2 - 1
    }
}

/// Counts how often a stepped track changed value since its clock started, so each
/// change picks new random numbers and the same time always gives the same bolt.
nonisolated enum LightningTrackCount {
    static func changes(
        _ keys: [NIFKey<Bool>], timing: ControllerTiming, seconds: Float
    ) -> UInt64 {
        guard keys.count > 1 else { return 0 }
        let span = timing.stopTime - timing.startTime
        let advanced = max(seconds, 0) * timing.frequency + timing.phase - timing.startTime
        guard span.isFinite, span > 0, advanced > 0 else {
            return within(keys, upTo: timing.startTime + max(advanced, 0))
        }
        let whole = within(keys, upTo: timing.stopTime)
        let passes = UInt64(min((advanced / span).rounded(.down), 1e9))
        let rest = advanced - Float(passes) * span
        switch timing.cycle {
        case .clamp:
            return within(keys, upTo: timing.startTime + min(advanced, span))
        case .loop:
            // The jump from the last key back to the first can be a change too.
            let wrap: UInt64 = keys.first?.value == keys.last?.value ? 0 : 1
            return passes * (whole + wrap) + within(keys, upTo: timing.startTime + rest)
        case .reverse:
            let partial = passes.isMultiple(of: 2)
                ? within(keys, upTo: timing.startTime + rest)
                : whole - within(keys, upTo: timing.stopTime - rest)
            return passes * whole + partial
        }
    }

    /// The changes between the first key and `time`.
    private static func within(_ keys: [NIFKey<Bool>], upTo time: Float) -> UInt64 {
        var count: UInt64 = 0
        for index in keys.indices.dropFirst() where keys[index].time <= time {
            count += keys[index].value == keys[index - 1].value ? 0 : 1
        }
        return count
    }
}
