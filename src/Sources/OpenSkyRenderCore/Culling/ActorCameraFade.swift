// Actors fade out when the camera comes close to them, so the camera never shows the
// inside of a body (docs/engine/actor-camera-fade.md).

import simd

nonisolated public struct ActorCameraFade: Equatable, Sendable {
    /// An actor the sweep hits fades when the hit is nearer to the eye than this plus the
    /// bounding radius of the node that owns the body it hit.
    public static let fadeOutLimit: Float = 30
    /// The radius of the sphere swept from the pivot to the eye.
    public static let probeRadius: Float = 15
    /// The sphere at the eye that fades the player.
    public static let playerProbeRadius: Float = 20
    /// Above the player's feet, the eye drops by the player's height minus this.
    public static let playerHeightOffset: Float = 124
    /// A seated player fades while the eye is this close to its head.
    public static let seatedRadius: Float = 45
    /// Seconds a full change of the amount takes, both ways: the teleport fade times.
    public static let actorSeconds: Float = 0.5
    public static let playerSeconds: Float = 0.001
    /// The drawn alpha follows the amount at this rate, and at most `alphaPerFrame` a frame.
    public static let alphaPerSecond: Float = 1
    public static let alphaPerFrame: Float = 0.1
    /// The player is never drawn below this alpha.
    public static let playerMinimumAlpha: Float = 0.1

    /// What the current camera does with the fade.
    public enum Camera: Equatable, Sendable {
        /// Third person and the other orbit cameras: a new fade may start.
        case startsFades
        /// First person: the tests run, but no new fade starts.
        case holdsFades
        /// The free camera and camera changes: no test runs.
        case frozen
    }

    /// Everything one frame's choice reads.
    public struct Scene: Equatable, Sendable {
        public var camera: Camera
        public var eye: SIMD3<Float>
        public var pivot: SIMD3<Float>
        public var actors: [Candidate]
        public var target: Target?

        public init(
            camera: Camera, eye: SIMD3<Float>, pivot: SIMD3<Float>, actors: [Candidate],
            target: Target?
        ) {
            self.camera = camera
            self.eye = eye
            self.pivot = pivot
            self.actors = actors
            self.target = target
        }
    }

    private struct Fade: Equatable {
        /// 1 shown, 0 gone.
        var amount: Float = 1
        var isFadingOut = true
        /// What the renderer draws; it follows the amount.
        var alpha: Float = 1
        var seconds: Float
        var minimumAlpha: Float

        /// Not fading out, and not still fading back in.
        var isNormal: Bool {
            !isFadingOut && amount >= 1
        }
    }

    private var fades: [UInt32: Fade] = [:]
    private var camera = Camera.frozen
    /// The one actor the camera holds faded out.
    public private(set) var chosen: UInt32?

    public init() {}

    /// Chooses this frame's actor and steps every fade by `seconds`. A nil scene is the
    /// frozen camera.
    public mutating func advance(scene: Scene?, seconds: Float) {
        let next = scene?.camera ?? .frozen
        // Entering or leaving the orbit cameras lets the held actor go.
        if (camera == .startsFades) != (next == .startsFades) {
            release()
        }
        camera = next
        if let scene, scene.camera != .frozen {
            pick(in: scene)
        }
        step(seconds: seconds.isFinite ? max(seconds, 0) : 0)
    }

    private mutating func pick(in scene: Scene) {
        let pick = Self.choose(
            eye: scene.eye, pivot: scene.pivot, actors: scene.actors, target: scene.target
        )
        let isPlayer = pick != nil && pick == scene.target?.formID
        guard pick != chosen else {
            // First person lets a player that fades out come back.
            if scene.camera == .holdsFades, isPlayer {
                release()
            }
            return
        }
        release()
        // An actor still fading back in is tried again next frame.
        guard let pick, scene.camera == .startsFades, fades[pick]?.isNormal ?? true else { return }
        var fade = fades[pick] ?? Fade(seconds: 0, minimumAlpha: 0)
        fade.isFadingOut = true
        fade.seconds = isPlayer ? Self.playerSeconds : Self.actorSeconds
        fade.minimumAlpha = isPlayer ? Self.playerMinimumAlpha : 0
        fades[pick] = fade
        chosen = pick
    }

    /// The held actor fades back in and is forgotten.
    private mutating func release() {
        if let old = chosen {
            fades[old]?.isFadingOut = false
        }
        chosen = nil
    }

    private mutating func step(seconds: Float) {
        for (formID, fade) in fades {
            var next = fade
            let change = seconds / max(fade.seconds, Self.playerSeconds)
            next.amount = next.isFadingOut
                ? max(next.amount - change, 0) : min(next.amount + change, 1)
            let target = max(next.amount, fade.minimumAlpha)
            let move = min(seconds * Self.alphaPerSecond, Self.alphaPerFrame)
            next.alpha += max(min(target - next.alpha, move), -move)
            fades[formID] = next.isNormal && next.alpha >= 1 ? nil : next
        }
    }

    /// How far each actor is drawn faded out, 0 to 1, by its reference.
    public var fadeOuts: [UInt32: Float] {
        fades.compactMapValues { $0.alpha < 1 ? 1 - $0.alpha : nil }
    }
}
