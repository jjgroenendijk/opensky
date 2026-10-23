// Trap blade contact for Papyrus `OnTrapHitStart`, `OnTrapHit`, and `OnTrapHitStop`
// (<https://ck.uesp.net/wiki/OnTrapHit_-_ObjectReference>). A trap's graph moves bones,
// not collision bodies, so a moving bone near an actor's capsule counts as contact.

import OpenSkyFormatsESM
import simd

/// One bone of a trap, in world space, this frame.
nonisolated public struct TrapContactPoint: Equatable, Sendable {
    public let position: SIMD3<Float>
    public let velocity: SIMD3<Float>

    public init(position: SIMD3<Float>, velocity: SIMD3<Float>) {
        self.position = position
        self.velocity = velocity
    }
}

/// A live actor a trap can hit: an upright capsule standing on `feet`.
nonisolated public struct TrapContactTarget: Equatable, Sendable {
    public let key: ReferenceKey
    public let feet: SIMD3<Float>
    public let radius: Float
    public let height: Float

    public init(key: ReferenceKey, feet: SIMD3<Float>, radius: Float, height: Float) {
        self.key = key
        self.feet = feet
        self.radius = radius
        self.height = height
    }

    func distance(to point: SIMD3<Float>) -> Float {
        let low = feet.z + radius
        let high = max(low, feet.z + height - radius)
        let axis = SIMD3(feet.x, feet.y, min(max(point.z, low), high))
        return max(0, simd_distance(point, axis) - radius)
    }
}

nonisolated public enum TrapContactEvent: Equatable, Sendable {
    /// First contact, and each repeat while contact lasts. `initial` is `abInitialHit`.
    case hit(trap: ReferenceKey, target: ReferenceKey, point: TrapContactPoint, initial: Bool)
    case stop(trap: ReferenceKey, target: ReferenceKey)
}

/// [WARNING] OpenSky's numbers: no open source gives the game's contact shapes or rate.
nonisolated public struct TrapContactSettings: Equatable, Sendable {
    /// How far from a bone a capsule still counts as touched, in game units.
    public var reach: Float = 24
    /// A bone slower than this, in units per second, is at rest and hits no one.
    public var minimumSpeed: Float = 60
    /// Seconds between two `OnTrapHit` events on one target.
    public var repeatInterval: Float = 0.25

    public init() {}
}

/// Tracks which traps touch which actors, so contact starts, repeats, and stops once.
nonisolated public struct TrapContactTracker: Sendable {
    private struct Pair: Hashable {
        let trap: ReferenceKey
        let target: ReferenceKey
    }

    public var settings = TrapContactSettings()
    private var touching: [Pair: Float] = [:]
    private var lastPositions: [ReferenceKey: [SIMD3<Float>]] = [:]

    public init() {}

    /// Velocities from the bone positions of the last frame. The first frame of a trap
    /// has no velocity, so it hits no one.
    public mutating func points(
        of trap: ReferenceKey, positions: [SIMD3<Float>], delta: Float
    ) -> [TrapContactPoint] {
        defer { lastPositions[trap] = positions }
        guard
            delta > 0, let last = lastPositions[trap], last.count == positions.count
        else { return positions.map { TrapContactPoint(position: $0, velocity: .zero) } }
        return zip(positions, last).map { now, before in
            TrapContactPoint(position: now, velocity: (now - before) / delta)
        }
    }

    /// One frame of one trap. Every target not touched this frame stops touching.
    public mutating func step(
        trap: ReferenceKey,
        points: [TrapContactPoint],
        targets: [TrapContactTarget],
        delta: Float
    ) -> [TrapContactEvent] {
        let moving = points.filter { simd_length($0.velocity) >= settings.minimumSpeed }
        var events: [TrapContactEvent] = []
        var touched: Set<ReferenceKey> = []
        for target in targets {
            guard
                let point = moving.min(by: {
                    target.distance(to: $0.position) < target.distance(to: $1.position)
                }),
                target.distance(to: point.position) <= settings.reach
            else { continue }
            touched.insert(target.key)
            let pair = Pair(trap: trap, target: target.key)
            guard let since = touching[pair] else {
                touching[pair] = 0
                events.append(.hit(trap: trap, target: target.key, point: point, initial: true))
                continue
            }
            let elapsed = since + max(0, delta)
            if elapsed >= settings.repeatInterval {
                touching[pair] = 0
                events.append(.hit(trap: trap, target: target.key, point: point, initial: false))
            } else {
                touching[pair] = elapsed
            }
        }
        for pair in touching.keys.sorted(by: { $0.target < $1.target })
            where pair.trap == trap && !touched.contains(pair.target)
        {
            touching.removeValue(forKey: pair)
            events.append(.stop(trap: trap, target: pair.target))
        }
        return events
    }

    /// Forgets the traps that left `resident`, so they start fresh when they return.
    public mutating func retain(_ resident: Set<ReferenceKey>) {
        lastPositions = lastPositions.filter { resident.contains($0.key) }
        touching = touching.filter { resident.contains($0.key.trap) }
    }
}
