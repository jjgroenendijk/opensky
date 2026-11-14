// Actors fade out when the camera comes close to them, so the camera never shows the
// inside of a body (docs/engine/graphics-options.md#actor-fade-near-the-camera).

public import OpenSkyFormatsCore
import simd

nonisolated public struct ActorCameraFade: Equatable, Sendable {
    /// `fActorFadeOutLimit:Camera`: an actor the probe hits fades when the hit is nearer
    /// to the camera than this plus the radius of the shape it hit.
    public static let fadeOutLimit: Float = 30
    /// `fCameraCasterSize:Camera`: the radius of the sphere swept from the pivot to the eye.
    public static let probeRadius: Float = 15
    /// `fCameraCasterTargetSize:Camera`: the sphere at the eye that fades the player.
    public static let playerProbeRadius: Float = 20
    /// `fCharControllerCheckHeightOffset:Camera`: above the player's feet, the eye is
    /// lowered by the player's height minus this before the player test.
    public static let playerHeightOffset: Float = 124
    /// The player's collision capsule radius, `PlayerCapsule.standard`.
    public static let playerRadius: Float = 24
    /// `fActorTeleportFadeSeconds`, for fading out and back in.
    public static let actorSeconds: Float = 0.5
    /// `fPlayerTeleportFadeSeconds`: the player fades at once.
    public static let playerSeconds: Float = 0.001

    /// One actor the camera may be inside: the world boxes of its drawn shapes.
    public struct Candidate: Equatable, Sendable {
        public let formID: UInt32
        public let shapes: [ModelBounds]
        public let isPlayer: Bool

        public init(formID: UInt32, shapes: [ModelBounds], isPlayer: Bool) {
            self.formID = formID
            self.shapes = shapes
            self.isPlayer = isPlayer
        }
    }

    /// Where along the probe a shape was hit, and that shape's bounding radius.
    private struct ProbeHit {
        let candidate: Candidate
        let along: Float
        let radius: Float
    }

    private struct Fade: Equatable {
        var visible: Float
        var seconds: Float
    }

    private var fades: [UInt32: Fade] = [:]
    public private(set) var chosen: UInt32?

    public init() {}

    /// The actor to fade this frame, or nil. `pivot` is the point the camera looks from,
    /// such as the third-person orbit point. It is nil in first person and the free
    /// camera, which never start a fade, so every faded actor fades back in.
    public static func choose(
        eye: SIMD3<Float>, pivot: SIMD3<Float>?, among candidates: [Candidate]
    ) -> Candidate? {
        guard let pivot else { return nil }
        if let player = candidates.first(where: \.isPlayer), touchesPlayer(eye, player) {
            return player
        }
        // The last actor the sphere hits on its way to the eye is the one the eye is in.
        var last: ProbeHit?
        for candidate in candidates where !candidate.isPlayer {
            for shape in candidate.shapes {
                guard let along = Self.entry(from: pivot, to: eye, into: shape) else { continue }
                if along >= (last?.along ?? -1) {
                    last = ProbeHit(
                        candidate: candidate, along: along,
                        radius: simd_length(shape.max - shape.min) / 2
                    )
                }
            }
        }
        guard let last else { return nil }
        let remaining = (1 - last.along) * simd_distance(pivot, eye)
        return remaining < fadeOutLimit + last.radius ? last.candidate : nil
    }

    /// The sphere at the eye touches the player's capsule, which stands upright at the
    /// centre of the player's shapes, from their lowest point to their highest. An eye
    /// above the feet is first lowered by the player's height minus `playerHeightOffset`,
    /// so a tall body fades sooner from above and a short one later.
    static func touchesPlayer(_ eye: SIMD3<Float>, _ player: Candidate) -> Bool {
        guard var box = player.shapes.first else { return false }
        for shape in player.shapes.dropFirst() {
            box = box.union(shape)
        }
        var point = eye
        if point.z > box.min.z {
            point.z -= (box.max.z - box.min.z) - playerHeightOffset
        }
        let centre = (box.min + box.max) / 2
        let height = min(max(point.z, box.min.z), box.max.z)
        let axis = SIMD3(centre.x, centre.y, height)
        return simd_distance(point, axis) < playerProbeRadius + playerRadius
    }

    /// How far along the line from `start` to `end` the probe sphere first touches
    /// `box`, from 0 to 1, or nil when it misses. The box grows by the probe radius,
    /// which keeps every true hit and adds a little at the corners.
    static func entry(
        from start: SIMD3<Float>, to end: SIMD3<Float>, into box: ModelBounds
    ) -> Float? {
        let low = box.min - SIMD3(repeating: probeRadius)
        let high = box.max + SIMD3(repeating: probeRadius)
        let direction = end - start
        guard simd_length_squared(direction) > .ulpOfOne else { return nil }
        var enter: Float = 0
        var leave: Float = 1
        for axis in 0 ..< 3 {
            if abs(direction[axis]) < .ulpOfOne {
                guard start[axis] >= low[axis], start[axis] <= high[axis] else { return nil }
                continue
            }
            let first = (low[axis] - start[axis]) / direction[axis]
            let second = (high[axis] - start[axis]) / direction[axis]
            enter = max(enter, min(first, second))
            leave = min(leave, max(first, second))
            guard enter <= leave else { return nil }
        }
        return enter
    }

    /// The chosen actor fades out; every other faded actor fades back in.
    public mutating func advance(
        eye: SIMD3<Float>, pivot: SIMD3<Float>?, candidates: [Candidate], seconds: Float
    ) {
        let pick = Self.choose(eye: eye, pivot: pivot, among: candidates)
        chosen = pick?.formID
        if let pick, fades[pick.formID] == nil {
            fades[pick.formID] = Fade(
                visible: 1, seconds: pick.isPlayer ? Self.playerSeconds : Self.actorSeconds
            )
        }
        let step = seconds.isFinite ? max(seconds, 0) : 0
        for (formID, fade) in fades {
            var next = fade
            let change = step / max(fade.seconds, Self.playerSeconds)
            next.visible = formID == chosen ? max(fade.visible - change, 0) : fade.visible + change
            fades[formID] = next.visible >= 1 ? nil : next
        }
    }

    /// How far each actor has faded out, 0 to 1, by its reference.
    public var fadeOuts: [UInt32: Float] {
        fades.mapValues { 1 - $0.visible }
    }
}
