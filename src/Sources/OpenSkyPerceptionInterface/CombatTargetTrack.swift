// What a combat group remembers of one target: noticed, lost, and where it was last
// known. See docs/engine/detection.md#keeping-a-combat-target.

import simd

/// The facts of one step that decide whether a target is kept or lost.
nonisolated public struct CombatTargetSighting: Equatable, Sendable {
    /// The highest detection value of any member.
    public var value: Float
    /// The value is above 0 and either the stealth points are 0 or it passed the threshold.
    public var counts: Bool
    /// The target's true position.
    public var position: SIMD3<Float>
    public var isInvisible = false
    /// A member has the target in its view cone with a line of sight.
    public var memberSeesTarget = false
    /// A member close to the last known position has a clear line to it.
    public var memberSeesLastKnown = false
    public var hasEngagedMember = false
    /// The distance from the target to the nearest engaged member.
    public var nearestMember: Float = .infinity

    public init(value: Float, counts: Bool, position: SIMD3<Float>) {
        self.value = value
        self.counts = counts
        self.position = position
    }
}

nonisolated public struct CombatTargetTrack: Equatable, Sendable {
    public enum Phase: String, Sendable {
        case hidden, noticed, lost
    }

    /// The last known position follows the target this long after a sighting.
    public static let followSeconds: Float = 10
    /// It follows only while the target stays this near where it was seen.
    public static let followRadius: Float = 768
    /// The target is lost this long after the last known position stopped following.
    public static let lostAfterSeconds: Float = 10
    /// A member this near the last known position can see that the target left.
    public static let lastKnownCheckRadius: Float = 256
    public static let dropSeconds: Float = 30
    /// With engaged members, the drop also needs this long with no member near.
    public static let farDropSeconds: Float = 60
    public static let nearMemberRadius: Float = 4096
    /// A hit by the target and a detection event cap the stealth points at these.
    public static let hitPointCap: Float = 50
    public static let eventPointCap: Float = 75

    public private(set) var phase = Phase.hidden
    /// The group has the target on its list: a member perceived it, or it hit a member.
    public private(set) var isListed = false
    public private(set) var seenAt: SIMD3<Float>?
    public private(set) var lastKnown: SIMD3<Float>?
    private var sinceSighting: Float = 0
    private var sinceFollowed: Float = 0
    public private(set) var lostSeconds: Float = 0
    private var farSeconds: Float = 0

    public init() {}

    /// One step. Returns true when the group drops the target; the record is then new.
    @discardableResult
    public mutating func advance(_ sighting: CombatTargetSighting, by seconds: Float) -> Bool {
        guard seconds.isFinite, seconds > 0 else { return false }
        if sighting.counts {
            self = Self()
            phase = .noticed
            isListed = true
            seenAt = sighting.position
            lastKnown = sighting.position
            return false
        }
        if phase == .noticed {
            follow(sighting, by: seconds)
        }
        if phase != .lost, isLost(sighting) {
            lose()
        }
        guard phase == .lost else { return false }
        lostSeconds += seconds
        farSeconds = sighting.nearestMember > Self.nearMemberRadius ? farSeconds + seconds : 0
        let isFarLongEnough = !sighting.hasEngagedMember || farSeconds >= Self.farDropSeconds
        guard lostSeconds >= Self.dropSeconds, isFarLongEnough else { return false }
        self = Self()
        return true
    }

    /// A place to search, from a hit or a detection event. A noticed target keeps its own.
    public mutating func addSearchPlace(_ position: SIMD3<Float>) {
        isListed = true
        if phase != .noticed {
            lastKnown = position
        }
    }

    private mutating func follow(_ sighting: CombatTargetSighting, by seconds: Float) {
        sinceSighting += seconds
        let isNear = seenAt.map {
            simd_distance($0, sighting.position) <= Self.followRadius
        } ?? false
        if sinceSighting < Self.followSeconds, isNear {
            lastKnown = sighting.position
            sinceFollowed = 0
            return
        }
        sinceFollowed += seconds
        if sinceFollowed >= Self.lostAfterSeconds {
            lose()
        }
    }

    /// The three rules that need no timer.
    private func isLost(_ sighting: CombatTargetSighting) -> Bool {
        if sighting.value > 0 {
            return true
        }
        guard isListed, sighting.value < 0 else { return false }
        if sighting.memberSeesTarget, phase != .noticed || sighting.isInvisible {
            return true
        }
        return phase != .noticed && sighting.memberSeesLastKnown
    }

    private mutating func lose() {
        phase = .lost
        isListed = true
        lostSeconds = 0
        farSeconds = 0
    }
}
