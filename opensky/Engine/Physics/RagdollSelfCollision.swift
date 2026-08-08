// Which of a ragdoll's own bones are allowed to collide with each other
// (issue #413, split from #407).
//
// Item 15.6 shipped with self-collision switched off wholesale, because a
// vanilla humanoid is eighteen capsules whose radii run to eighteen engine units
// on bones about twenty long: they overlap heavily by construction, and every
// overlap pushes while every joint pulls back. Measured at the bind pose, 24 of
// the 153 possible pairs are already interpenetrating before anything moves, the
// deepest by 12 engine units.
//
// Havok does not admit those pairs either, and the file says which ones it does:
// a `bhkRigidBody`'s `HavokFilter` carries a biped part number. This type reads
// that number and turns it into the pair set.
//
// ## What the file carries
//
// nif.xml's `CollisionFilterFlags` is a bitfield over the filter's one flags
// byte: bits 0-4 are a `BipedPart`, bit 5 `MOPP Scaled`, bit 6 `No Collision`,
// bit 7 `Linked Group`. The part number is documented as meaningful "only if the
// Layer is 8 (or 32/33 for Skyrim and later)", which is `SKYL_BIPED`,
// `SKYL_DEADBIP` and `SKYL_BIPED_NO_CC`.
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
//
// The vanilla humanoid `skeleton.nif` confirms the reading rather than merely
// being consistent with it. All eighteen bodies sit on layer 8 in group 0 with
// no `No Collision` bit, and every part number lands on the anatomically correct
// `BipedPart` name: `NPC Head` reads 1 (`P_HEAD`), `NPC L UpperArm` 5
// (`P_L_UPPER_ARM`), `NPC L Calf` 9 (`P_L_CALF`), `NPC R Foot` 16 (`P_R_FOOT`),
// and so on through all sixteen distinct values. That anatomy could not line up
// by accident with a mask read at the wrong width or offset.
//
// ## Which pairs are admitted
//
// Havok does not publish its biped pair table, so what the part numbers are used
// for here is stated rather than assumed:
//
//  1. **Both bodies must carry a part number at all.** A body on a non-biped
//     layer says nothing about biped self-collision, so nothing is admitted for
//     it.
//  2. **Neither may carry `No Collision`.** The one bit in the byte whose
//     meaning is unambiguous.
//  3. **The two part numbers must differ.** Two bodies sharing a part are the
//     same anatomical part modelled twice, and the vanilla humanoid does exactly
//     that: `NPC COM` and `NPC Spine` both read 2 (`P_BODY`), and they are the
//     second-deepest overlap in the whole skeleton.
//  4. **The two bodies must be more than two joints apart** in the ragdoll's own
//     joint graph. One hop is what a constraint means — a joint holds two bodies
//     together at a shared pivot, so their capsules necessarily overlap there.
//     Two hops is the pair a shared parent holds together: left thigh against
//     right thigh at the pelvis, upper arm against spine at the shoulder, head
//     against spine through the neck.
//
// Rule 4 is a graph distance rather than a hard-coded anatomical table on the
// part numbers, and that is deliberate. It is derived from the same file the
// bodies came out of, so a skeleton that is not a biped at all — a dragon, a
// spider, a mod's creature — gets the same treatment without anyone writing its
// anatomy down. It also cannot silently admit a pair the constraint data says is
// jointed.
//
// The measured effect on the vanilla humanoid: 63 of 153 pairs admitted, and
// **zero of them overlap at the bind pose**, against 24 overlapping pairs with
// everything switched on. So the corpse gets a torso its arms cannot pass
// through, and the solver never sees the standing contacts that made 15.6 turn
// the whole thing off.
//
// Documented in docs/engine/ragdoll.md.

/// One unordered pair of bone indices, `first < second`.
nonisolated struct RagdollBonePair: Hashable, Sendable, Comparable {
    let first: Int
    let second: Int

    init(_ one: Int, _ other: Int) {
        first = min(one, other)
        second = max(one, other)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.first, lhs.second) < (rhs.first, rhs.second)
    }
}

/// The bone pairs of one ragdoll that are allowed to collide.
nonisolated struct RagdollSelfCollision: Sendable, Equatable {
    /// How many joints apart two bones must be before they may touch. Two hops
    /// is a jointed pair's shared parent, so the first admitted distance is
    /// three.
    static let minimumJointDistance = 3

    /// Admitted pairs, ascending. Sorted rather than a bare set so anything that
    /// reports or iterates them is deterministic.
    let pairs: [RagdollBonePair]
    private let admitted: Set<RagdollBonePair>

    /// Nothing collides with anything: the 15.6 behaviour, and what a ragdoll
    /// whose bodies carry no biped parts falls back to.
    static let disabled = Self(pairs: [])

    private init(pairs: [RagdollBonePair]) {
        self.pairs = pairs
        admitted = Set(pairs)
    }

    var pairCount: Int {
        pairs.count
    }

    func admits(_ one: Int, _ other: Int) -> Bool {
        one != other && admitted.contains(RagdollBonePair(one, other))
    }

    /// The admitted set for one ragdoll, from its bones' biped parts and its own
    /// joint graph. See the file header for what each rule is doing.
    init(bones: [RagdollBoneDefinition], joints: [RagdollJointDefinition]) {
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
