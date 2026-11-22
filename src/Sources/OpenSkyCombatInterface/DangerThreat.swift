// What counts as a danger to an actor, and how a fighter scores it and picks a sidestep.
// Pure. See docs/engine/danger-avoidance.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
import simd

/// Something that will explode near an actor soon.
nonisolated public struct DangerThreat: Equatable, Sendable {
    public var id: Int
    /// Who sent it, so its own side can ignore it.
    public var source: ReferenceKey?
    public var position: SIMD3<Float>
    /// Its travel in units a second. Zero for a threat that waits where it is.
    public var velocity: SIMD3<Float>
    public var damage: Float
    /// The distance inside which it deals at least `DangerRule.minimumDamage`.
    public var radius: Float

    public init(
        id: Int, source: ReferenceKey? = nil, position: SIMD3<Float>,
        velocity: SIMD3<Float> = .zero, damage: Float, radius: Float
    ) {
        self.id = id
        self.source = source
        self.position = position
        self.velocity = velocity
        self.damage = damage
        self.radius = radius
    }
}

/// The fighter a threat is scored for.
nonisolated public struct DangerActor: Equatable, Sendable {
    public var feet: SIMD3<Float>
    public var radius: Float
    /// Current `Health`.
    public var health: Float
    /// Move speed in units a second.
    public var speed: Float
    /// A moving actor reacts later than a standing one.
    public var isMoving = false
    /// Where a moving actor walks to. Nil for a standing one.
    public var goal: SIMD3<Float>?

    public init(feet: SIMD3<Float>, radius: Float, health: Float, speed: Float) {
        self.feet = feet
        self.radius = radius
        self.health = health
        self.speed = speed
    }
}

/// The dodge numbers. `fCombatDodge*` game settings.
nonisolated public struct DangerSettings: Equatable, Sendable {
    public var reactionTime: Float = 0.15
    public var movingReactionTime: Float = 0.25
    public var anticipateTime: Float = 2
    public var bufferDistance: Float = 64
    public var acceptableScoreMult: Float = 0.5
    public var chanceMin: Float = 0
    public var chanceMax: Float = 1
    /// Seconds between two looks at the threat list.
    public var sampleSeconds: ClosedRange<Float> = 0.125 ... 0.25

    public static let vanilla = DangerSettings()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fCombatDodgeReactionTime", into: &settings, \.reactionTime)
        store.read("fCombatDodgeMovingReactionTime", into: &settings, \.movingReactionTime)
        store.read("fCombatDodgeAnticipateThreatTime", into: &settings, \.anticipateTime)
        store.read("fCombatDodgeBufferDistance", into: &settings, \.bufferDistance)
        store.read(
            "fCombatDodgeAcceptableThreatScoreMult", into: &settings, \.acceptableScoreMult
        )
        store.read("fCombatDodgeChanceMin", into: &settings, \.chanceMin)
        store.read("fCombatDodgeChanceMax", into: &settings, \.chanceMax)
        return settings
    }

    /// The chance to dodge for a combat style's Avoid Threat Chance.
    public func chance(style: Float) -> Float {
        chanceMin + (chanceMax - chanceMin) * style
    }
}

/// The sidestep a fighter takes.
nonisolated public struct DangerDodge: Equatable, Sendable {
    public var point: SIMD3<Float>
    /// Seconds the move takes at the actor's speed.
    public var seconds: Float
    public var threat: Int
}

/// One fighter's watch on the threat list.
nonisolated public struct CombatDangerWatch: Equatable, Sendable {
    /// Seconds until the next look.
    public var untilSample: Float = 0
    /// Seconds left of a sidestep, 0 when it does none.
    public var dodgeSeconds: Float = 0
    /// The score of the last look over the anticipate time.
    public var score: Float = 0
    public var dodge: DangerDodge?
    public var dodgeCount = 0

    public init() {}
}

nonisolated public enum DangerRule {
    /// A projectile's explosion is a threat from this damage.
    public static let minimumDamage: Float = 5
    /// And from this effective radius at that damage.
    public static let minimumRadius: Float = 30

    /// The distance inside which an explosion deals at least `threshold`:
    /// R × √(1 − T / D), or 0 when T is larger than D.
    public static func effectiveRadius(damage: Float, radius: Float, threshold: Float) -> Float {
        guard damage > 0, threshold <= damage else { return 0 }
        return radius * (1 - threshold / damage).squareRoot()
    }

    /// The threat of a projectile or explosion on its way, or nil when it is too small.
    public static func threat(
        id: Int, source: ReferenceKey?,
        motion: (position: SIMD3<Float>, velocity: SIMD3<Float>),
        explosion: (damage: Float, radius: Float)
    ) -> DangerThreat? {
        let (damage, radius) = explosion
        guard damage >= minimumDamage else { return nil }
        let effective = effectiveRadius(damage: damage, radius: radius, threshold: minimumDamage)
        guard effective >= minimumRadius else { return nil }
        return DangerThreat(
            id: id, source: source, position: motion.position, velocity: motion.velocity,
            damage: damage, radius: effective
        )
    }

    /// Whether `threat` counts for an actor at `feet` over the next `seconds`: the actor
    /// is ahead of it, and the space it sweeps through overlaps the actor's bounds.
    public static func counts(
        _ threat: DangerThreat, at feet: SIMD3<Float>, radius: Float, seconds: Float
    ) -> Bool {
        let offset = feet - threat.position
        guard simd_dot(offset, threat.velocity) >= 0 else { return false }
        let sweep = threat.velocity * max(0, seconds)
        let length = simd_length_squared(sweep)
        let along = length > 0 ? min(1, max(0, simd_dot(offset, sweep) / length)) : 0
        return simd_distance(offset, sweep * along) <= threat.radius + radius
    }

    /// The sum of the counted threats' damage over the actor's current `Health`.
    public static func score(
        _ threats: [DangerThreat], for actor: DangerActor, at feet: SIMD3<Float>? = nil,
        seconds: Float
    ) -> Float {
        guard actor.health > 0 else { return 0 }
        let damage = threats
            .filter { counts($0, at: feet ?? actor.feet, radius: actor.radius, seconds: seconds) }
            .reduce(0) { $0 + $1.damage }
        return damage / actor.health
    }

    /// The score an actor collects while it moves to `point` in `seconds`: a threat
    /// counts when it comes within reach of the actor at one of 8 moments of the move.
    static func movingScore(
        _ threats: [DangerThreat], for actor: DangerActor, to point: SIMD3<Float>,
        seconds: Float
    ) -> Float {
        guard actor.health > 0 else { return 0 }
        let damage = threats.filter { threat in
            (1 ... 8).contains { sample in
                let part = Float(sample) / 8
                let feet = actor.feet + (point - actor.feet) * part
                let place = threat.position + threat.velocity * (seconds * part)
                return simd_distance(feet, place) <= threat.radius + actor.radius
            }
        }
        .reduce(0) { $0 + $1.damage }
        return damage / actor.health
    }

    /// The score a moving actor collects on its straight path to its goal over the next
    /// `seconds`, and the worst threat on it. A standing actor is scored where it stands.
    public static func aheadScore(
        _ threats: [DangerThreat], for actor: DangerActor, seconds: Float
    ) -> Float {
        guard let end = pathEnd(of: actor, seconds: seconds) else {
            return score(threats, for: actor, seconds: seconds)
        }
        return movingScore(threats, for: actor, to: end, seconds: seconds)
    }

    /// Where the actor is on its path after `seconds`, or nil when it stands.
    static func pathEnd(of actor: DangerActor, seconds: Float) -> SIMD3<Float>? {
        guard actor.isMoving, let goal = actor.goal else { return nil }
        let path = goal - actor.feet
        let length = simd_length(path)
        guard length > 1e-3 else { return nil }
        return actor.feet + path / length * min(length, actor.speed * max(0, seconds))
    }

    /// The threats a look-ahead counts: on the path of a moving actor, else where it stands.
    static func counted(
        _ threats: [DangerThreat], for actor: DangerActor, seconds: Float
    ) -> [DangerThreat] {
        guard let end = pathEnd(of: actor, seconds: seconds) else {
            return threats.filter {
                counts($0, at: actor.feet, radius: actor.radius, seconds: seconds)
            }
        }
        return threats.filter { movingScore([$0], for: actor, to: end, seconds: seconds) > 0 }
    }

    /// The two escape points for the most significant threat, the preferred side first.
    /// Each is at a right angle to the threat's line of travel on the ground plane.
    /// `coin` picks the side when the actor is under half its radius from the line.
    public static func escapePoints(
        from threat: DangerThreat, for actor: DangerActor, settings: DangerSettings, coin: Bool
    ) -> [SIMD3<Float>] {
        var line = SIMD2(threat.velocity.x, threat.velocity.y)
        if simd_length_squared(line) < 1e-6, actor.isMoving, let goal = actor.goal {
            // A threat that waits on a walker's path: the walker's own travel is the line.
            line = SIMD2(actor.feet.x - goal.x, actor.feet.y - goal.y)
        }
        if simd_length_squared(line) < 1e-6 {
            // A threat that waits has no line: the actor leaves straight away from it.
            line = SIMD2(actor.feet.y - threat.position.y, threat.position.x - actor.feet.x)
        }
        guard simd_length_squared(line) >= 1e-6 else { return [] }
        line = simd_normalize(line)
        let normal = SIMD2(-line.y, line.x)
        let offset = simd_dot(
            SIMD2(actor.feet.x - threat.position.x, actor.feet.y - threat.position.y), normal
        )
        let own: Float = abs(offset) < actor.radius / 2 ? (coin ? 1 : -1) : (offset < 0 ? -1 : 1)
        let reach = threat.radius + actor.radius + settings.bufferDistance
        return [own, -own].map { side in
            let distance = reach - offset * side
            let step = normal * side * max(0, distance)
            return actor.feet + SIMD3(step.x, step.y, 0)
        }
    }

    /// The sidestep, or nil when the danger is acceptable or no point is safe.
    /// `reaches` says whether the navmesh reaches a point.
    public static func dodge(
        from threats: [DangerThreat], for actor: DangerActor,
        settings: (numbers: DangerSettings, coin: Bool), reaches: (SIMD3<Float>) -> Bool
    ) -> DangerDodge? {
        let (settings, coin) = settings
        let ahead = settings.anticipateTime
        let reference = aheadScore(threats, for: actor, seconds: ahead)
        guard reference > 0, actor.speed > 0 else { return nil }
        let reaction = actor.isMoving ? settings.movingReactionTime : settings.reactionTime
        guard score(threats, for: actor, seconds: reaction) < reference else { return nil }
        let counted = counted(threats, for: actor, seconds: ahead)
        guard let worst = counted.max(by: { ($0.damage, $1.id) < ($1.damage, $0.id) }) else {
            return nil
        }
        let points = escapePoints(from: worst, for: actor, settings: settings, coin: coin)
        for point in points where reaches(point) {
            let seconds = simd_distance(point, actor.feet) / actor.speed
            let moving = movingScore(threats, for: actor, to: point, seconds: seconds)
            guard moving < settings.acceptableScoreMult * reference, score(
                threats,
                for: actor,
                at: point,
                seconds: ahead
            ) == 0 else { continue }
            return DangerDodge(point: point, seconds: seconds, threat: worst.id)
        }
        return nil
    }
}
