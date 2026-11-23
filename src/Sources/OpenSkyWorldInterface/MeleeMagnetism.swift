// Melee magnetism: on foot, the player's view turns a little with the object under the
// crosshair. Pure; the game session applies the change.
// docs/engine/combat-assist.md#melee-magnetism.

public import OpenSkyFormatsESM
import simd

nonisolated public enum MeleeMagnetism {
    /// The three multipliers of the rule, one set for an actor and one for an object.
    public struct Factors: Equatable, Sendable {
        public var strafeHeading: Float
        public var heading: Float
        public var looking: Float

        /// `fMagnetismStrafeHeadingMult`, `fMagnetismHeadingMult`, `fMagnetismLookingMult`.
        public static let actor = Self(strafeHeading: 0.5, heading: 1, looking: 10)
        /// The same three settings with `Obj` in the name.
        public static let object = Self(strafeHeading: 0, heading: 0.5, looking: 0.5)
    }

    /// `fMagnetismStrafeBaseSpeed`: both speed terms are divided by this.
    public static let baseSpeed: Float = 350
    /// `fMagnetismStrafeMaxDistance`: the rule fades to nothing at this distance.
    public static let maximumDistance: Float = 750
    /// The turning speed the look term reads, in radians a second. Ours: the general
    /// actor turn speed.
    public static let turnSpeed: Float = 2 * .pi

    /// The object under the crosshair, as the world reports it.
    public struct Sighting: Equatable, Sendable {
        /// The actor, or nil for any other object.
        public var actor: ReferenceKey?
        public var position: SIMD3<Float>

        public init(actor: ReferenceKey?, position: SIMD3<Float>) {
            self.actor = actor
            self.position = position
        }
    }

    /// What one frame of the rule reads.
    public struct Frame: Equatable, Sendable {
        /// The player's speed, and the strafe input from -1 (left) to 1 (right).
        public var speed: Float = 0
        public var strafe: Float = 0
        /// The view's heading as a yaw: counter-clockwise, with `cos` on x and `sin` on y.
        public var heading: Float = 0
        /// How far the look input turned the yaw and the pitch this frame, in radians.
        public var look = SIMD2<Float>.zero
        public var weaponDrawn = false
        public var isRiding = false
        public var targetIsActor = false
        public var distance: Float = 0
        /// The target's travel on the ground plane, in units a second.
        public var targetVelocity = SIMD2<Float>.zero
        public var deltaTime: Float = 0

        public init() {}

        var factors: Factors {
            targetIsActor ? .actor : .object
        }
    }

    /// The turn of one frame, in radians: `heading` is added to the yaw, `pitch` to the pitch.
    public struct Change: Equatable, Sendable {
        public var heading: Float = 0
        public var pitch: Float = 0

        public static let none = Self()

        public init(heading: Float = 0, pitch: Float = 0) {
            self.heading = heading
            self.pitch = pitch
        }
    }

    /// The rule does nothing while riding, with all inputs at zero, or at an actor while
    /// the weapon is sheathed. A target that is gone or dead gives no frame at all.
    public static func stops(_ frame: Frame) -> Bool {
        if frame.isRiding || frame.deltaTime <= 0 {
            return true
        }
        if frame.strafe == 0, frame.look == .zero {
            return true
        }
        return frame.targetIsActor && !frame.weaponDrawn
    }

    /// The strafe term: the player's speed × the strafe input / 350.
    public static func strafeTerm(_ frame: Frame) -> Float {
        frame.speed * frame.strafe / baseSpeed
    }

    /// The target term, only for a moving actor: the angle between its direction of
    /// travel and the heading, folded into -90 to 90 degrees, × its speed / 350 × -2/π.
    public static func targetTerm(_ frame: Frame) -> Float {
        let speed = simd_length(frame.targetVelocity)
        guard frame.targetIsActor, speed > 0 else { return 0 }
        let travel = atan2(frame.targetVelocity.y, frame.targetVelocity.x)
        var angle = remainder(travel - frame.heading, 2 * Float.pi)
        if angle > .pi / 2 {
            angle = .pi - angle
        } else if angle < -.pi / 2 {
            angle = -.pi - angle
        }
        return angle * speed / baseSpeed * (-2 / .pi)
    }

    /// 1 at the target and 0 at 750 units or more.
    public static func fade(_ frame: Frame) -> Float {
        max(0, 1 - frame.distance / maximumDistance)
    }

    /// The turn of this frame. The signs are for a yaw: a strafe to the right and a
    /// target that moves to the left both turn the view to the left, toward the target.
    public static func change(_ frame: Frame) -> Change {
        let fade = fade(frame)
        guard !stops(frame), fade > 0 else { return .none }
        let factors = frame.factors
        let lookScale = turnSpeed / .pi * frame.deltaTime
        let strafing = (strafeTerm(frame) - targetTerm(frame)) * factors.strafeHeading
            * frame.deltaTime * fade
        let change = Change(
            heading: strafing + frame.look.x * lookScale * factors.heading,
            pitch: frame.look.y * lookScale * factors.looking
        )
        return change.heading.isFinite && change.pitch.isFinite ? change : .none
    }
}

/// Runs the rule frame after frame: it reads the target's travel from two sightings and
/// keeps the last turn for `state assist`.
nonisolated public struct MeleeMagnetismTracker: Equatable, Sendable {
    /// The launcher's "Melee magnetism" switch.
    public var isEnabled = true
    /// The target of the last frame that turned the view, and its turn.
    public private(set) var lastTarget: MeleeMagnetism.Sighting?
    public private(set) var lastChange = MeleeMagnetism.Change.none
    /// True when the last frame turned the view.
    public private(set) var isTurning = false
    private var previous: MeleeMagnetism.Sighting?

    public init() {}

    /// The turn of one frame. `frame` carries everything but the target; `eye` is where
    /// the distance is measured from.
    public mutating func step(
        _ frame: MeleeMagnetism.Frame, sighting: MeleeMagnetism.Sighting?, eye: SIMD3<Float>
    ) -> MeleeMagnetism.Change {
        defer { previous = sighting }
        isTurning = false
        guard isEnabled, let sighting else { return .none }
        var frame = frame
        frame.targetIsActor = sighting.actor != nil
        frame.distance = simd_distance(eye, sighting.position)
        if let previous, previous.actor == sighting.actor, frame.deltaTime > 0 {
            let travel = sighting.position - previous.position
            frame.targetVelocity = SIMD2(travel.x, travel.y) / frame.deltaTime
        }
        let change = MeleeMagnetism.change(frame)
        guard change != .none else { return .none }
        isTurning = true
        lastTarget = sighting
        lastChange = change
        return change
    }
}
