// Actors fade out when the camera comes close to them, so the camera never shows the
// inside of a body (docs/engine/graphics-options.md#actor-fade-near-the-camera).

import simd

nonisolated public struct ActorCameraFade: Equatable, Sendable {
    /// The game picks an actor nearer to the camera than this plus the actor's radius.
    public static let reach: Float = 30
    public static let actorSeconds: Float = 0.5
    /// The game fades the player at once.
    public static let playerSeconds: Float = 0.001

    /// One actor the camera may be inside: its vertical axis and its collision radius.
    public struct Candidate: Equatable, Sendable {
        public let formID: UInt32
        public let feet: SIMD3<Float>
        public let height: Float
        public let radius: Float
        public let isPlayer: Bool

        public init(
            formID: UInt32,
            feet: SIMD3<Float>,
            height: Float,
            radius: Float,
            isPlayer: Bool
        ) {
            self.formID = formID
            self.feet = feet
            self.height = height
            self.radius = radius
            self.isPlayer = isPlayer
        }

        /// The eye's distance from the actor's vertical axis, between its feet and head.
        func distance(from eye: SIMD3<Float>) -> Float {
            let height = min(max(eye.z - feet.z, 0), max(height, 0))
            return simd_distance(eye, feet + SIMD3(0, 0, height))
        }
    }

    private struct Fade: Equatable {
        var visible: Float
        var seconds: Float
    }

    private var fades: [UInt32: Fade] = [:]
    public private(set) var chosen: UInt32?

    public init() {}

    /// The nearest candidate the eye is within reach of; nil when none is.
    public static func choose(eye: SIMD3<Float>, among candidates: [Candidate]) -> Candidate? {
        candidates
            .map { (candidate: $0, distance: $0.distance(from: eye)) }
            .filter { $0.distance < reach + $0.candidate.radius }
            .min { $0.distance < $1.distance }?
            .candidate
    }

    /// The chosen actor fades out; every other faded actor fades back in.
    public mutating func advance(eye: SIMD3<Float>, candidates: [Candidate], seconds: Float) {
        let pick = Self.choose(eye: eye, among: candidates)
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
