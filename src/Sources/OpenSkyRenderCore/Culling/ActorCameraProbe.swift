// Which actor the camera is too close to: a sphere swept from the pivot to the eye against
// each actor's collision capsules, and a sphere at the eye against the player's own capsule
// (docs/engine/actor-camera-fade.md#which-actor-fades).

import simd

nonisolated extension ActorCameraFade {
    /// One collision capsule of an actor; a sphere when `start == end`.
    public struct Body: Equatable, Sendable {
        public let start: SIMD3<Float>
        public let end: SIMD3<Float>
        public let radius: Float
        /// The bounding radius of the node that owns this body, which the fade limit adds.
        public let boundRadius: Float

        public init(start: SIMD3<Float>, end: SIMD3<Float>, radius: Float, boundRadius: Float) {
            self.start = start
            self.end = end
            self.radius = radius
            self.boundRadius = boundRadius
        }

        /// A bone body, whose node bound is taken as the capsule's own bound.
        public init(start: SIMD3<Float>, end: SIMD3<Float>, radius: Float) {
            self.init(
                start: start, end: end, radius: radius,
                boundRadius: simd_distance(start, end) / 2 + radius
            )
        }
    }

    /// A living actor other than the player, with the bodies the camera sweep can touch.
    public struct Candidate: Equatable, Sendable {
        public let formID: UInt32
        public let bodies: [Body]

        public init(formID: UInt32, bodies: [Body]) {
            self.formID = formID
            self.bodies = bodies
        }
    }

    /// The player as the camera target: its movement capsule, and its head while it sits.
    public struct Target: Equatable, Sendable {
        public let formID: UInt32
        public let feet: SIMD3<Float>
        public let radius: Float
        public let height: Float
        public let seatedHead: SIMD3<Float>?

        public init(
            formID: UInt32, feet: SIMD3<Float>, radius: Float, height: Float,
            seatedHead: SIMD3<Float>?
        ) {
            self.formID = formID
            self.feet = feet
            self.radius = radius
            self.height = height
            self.seatedHead = seatedHead
        }
    }

    /// Where the sweep touched a body, and the bound of the node that owns it.
    private struct ProbeHit {
        let along: Float
        let contact: SIMD3<Float>
        let bound: Float
    }

    /// The actor to fade this frame, or nil: the last actor the sweep touches when it is
    /// near enough to the eye, else the player when the eye is inside it.
    public static func choose(
        eye: SIMD3<Float>, pivot: SIMD3<Float>, actors: [Candidate], target: Target?
    ) -> UInt32? {
        var last: (formID: UInt32, hit: ProbeHit)?
        for actor in actors {
            for body in actor.bodies {
                guard let hit = sweep(from: pivot, to: eye, against: body) else { continue }
                if hit.along >= (last?.hit.along ?? -1) {
                    last = (actor.formID, ProbeHit(
                        along: hit.along, contact: hit.contact, bound: body.boundRadius
                    ))
                }
            }
        }
        if let last, simd_distance(last.hit.contact, eye) < fadeOutLimit + last.hit.bound {
            return last.formID
        }
        guard let target, isInside(eye: eye, target: target) else { return nil }
        return target.formID
    }

    /// The eye is inside the target: within the seated radius of its head while it sits,
    /// else the eye sphere overlaps its capsule after the eye drops by the height above 124.
    static func isInside(eye: SIMD3<Float>, target: Target) -> Bool {
        if let head = target.seatedHead {
            return simd_distance(eye, head) < seatedRadius
        }
        var point = eye
        if point.z > target.feet.z {
            point.z -= target.height - playerHeightOffset
        }
        let radius = max(target.radius, 0)
        let lower = target.feet + SIMD3(0, 0, radius)
        let upper = target.feet + SIMD3(0, 0, max(target.height - radius, radius))
        return distance(point, segment: (lower, upper)) < playerProbeRadius + radius
    }

    /// Where the probe sphere first touches `body` along the line from `start` to `end`:
    /// the share of the line, 0 to 1, and the contact point on the sphere. Nil on a miss.
    static func sweep(
        from start: SIMD3<Float>, to end: SIMD3<Float>, against body: Body
    ) -> (along: Float, contact: SIMD3<Float>)? {
        let reach = probeRadius + body.radius
        let segment = (body.start, body.end)
        func gap(_ along: Float) -> Float {
            distance(start + (end - start) * along, segment: segment)
        }
        // The distance from a moving point to a segment is convex in time: find its least
        // value, then the first time it falls within reach.
        var low: Float = 0
        var high: Float = 1
        for _ in 0 ..< 40 {
            let first = low + (high - low) / 3
            let second = high - (high - low) / 3
            if gap(first) <= gap(second) {
                high = second
            } else {
                low = first
            }
        }
        let nearest = (low + high) / 2
        guard gap(nearest) <= reach else { return nil }
        var along: Float = 0
        if gap(0) > reach {
            var outside: Float = 0
            var inside = nearest
            for _ in 0 ..< 30 {
                let middle = (outside + inside) / 2
                if gap(middle) > reach {
                    outside = middle
                } else {
                    inside = middle
                }
            }
            along = inside
        }
        let centre = start + (end - start) * along
        let toward = closestPoint(onSegment: segment, to: centre) - centre
        let length = simd_length(toward)
        let contact = length > .ulpOfOne
            ? centre + toward / length * min(probeRadius, length) : centre
        return (along, contact)
    }

    static func distance(
        _ point: SIMD3<Float>, segment: (SIMD3<Float>, SIMD3<Float>)
    ) -> Float {
        simd_distance(point, closestPoint(onSegment: segment, to: point))
    }

    static func closestPoint(
        onSegment segment: (SIMD3<Float>, SIMD3<Float>), to point: SIMD3<Float>
    ) -> SIMD3<Float> {
        let axis = segment.1 - segment.0
        let squared = simd_length_squared(axis)
        guard squared > .ulpOfOne else { return segment.0 }
        let along = simd_clamp(simd_dot(point - segment.0, axis) / squared, 0, 1)
        return segment.0 + axis * along
    }
}
