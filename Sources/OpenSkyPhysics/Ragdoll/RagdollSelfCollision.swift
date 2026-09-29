// Which of a ragdoll's own bones may collide with each other. It reads the biped
// part number in each `bhkRigidBody`'s `HavokFilter`. A pair collides when both
// bodies have a part, neither has `No Collision`, the parts differ, and the bodies
// are more than two joints apart. Documented in docs/engine/ragdoll-solver.md.

/// One unordered pair of bone indices, `first < second`.
nonisolated public struct RagdollBonePair: Hashable, Sendable, Comparable {
    public let first: Int
    public let second: Int

    public init(_ one: Int, _ other: Int) {
        first = min(one, other)
        second = max(one, other)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.first, lhs.second) < (rhs.first, rhs.second)
    }
}

/// The bone pairs of one ragdoll that are allowed to collide.
nonisolated public struct RagdollSelfCollision: Sendable, Equatable {
    /// How many joints apart two bones must be before they may touch. Two hops
    /// is a jointed pair's shared parent, so the first admitted distance is
    /// three.
    public static let minimumJointDistance = 3

    /// Admitted pairs, ascending. Sorted rather than a bare set so anything that
    /// reports or iterates them is deterministic.
    public let pairs: [RagdollBonePair]
    private let admitted: Set<RagdollBonePair>

    /// Nothing collides with anything: the 15.6 behaviour, and what a ragdoll
    /// whose bodies carry no biped parts falls back to.
    public static let disabled = Self(pairs: [])

    private init(pairs: [RagdollBonePair]) {
        self.pairs = pairs
        admitted = Set(pairs)
    }

    public var pairCount: Int {
        pairs.count
    }

    public func admits(_ one: Int, _ other: Int) -> Bool {
        one != other && admitted.contains(RagdollBonePair(one, other))
    }

    /// The admitted set for one ragdoll, from its bones' biped parts and its own
    /// joint graph.
    public init(bones: [RagdollBoneDefinition], joints: [RagdollJointDefinition]) {
        let neighbours = Self.neighbours(count: bones.count, joints: joints)
        var pairs: [RagdollBonePair] = []
        for first in bones.indices {
            guard let partA = bones[first].bipedPart else { continue }
            for second in bones.indices where second > first {
                guard
                    let partB = bones[second].bipedPart,
                    partA != partB,
                    Self.isFarEnough(first, second, neighbours: neighbours)
                else { continue }
                pairs.append(RagdollBonePair(first, second))
            }
        }
        self.init(pairs: pairs)
    }

    /// Which bones each bone is jointed to directly.
    private static func neighbours(
        count: Int,
        joints: [RagdollJointDefinition]
    ) -> [Set<Int>] {
        var neighbours = [Set<Int>](repeating: [], count: count)
        for joint in joints {
            guard
                neighbours.indices.contains(joint.bodyA),
                neighbours.indices.contains(joint.bodyB)
            else { continue }
            neighbours[joint.bodyA].insert(joint.bodyB)
            neighbours[joint.bodyB].insert(joint.bodyA)
        }
        return neighbours
    }

    /// Whether two bones are more than two joints apart. One hop is a direct
    /// joint; two hops is a shared neighbour. Both are read straight off the
    /// adjacency sets, because at this distance a search would only rediscover
    /// them.
    private static func isFarEnough(
        _ first: Int,
        _ second: Int,
        neighbours: [Set<Int>]
    ) -> Bool {
        guard neighbours.indices.contains(first), neighbours.indices.contains(second) else {
            return false
        }
        return !neighbours[first].contains(second)
            && neighbours[first].isDisjoint(with: neighbours[second])
    }
}
