// The first-person turn to the speaker when a conversation starts, and the look limits
// while it lasts. Angles follow `FreeFlyCamera`: yaw is the heading of the forward
// vector, and a positive pitch looks up. See docs/engine/dialogue-camera.md.

import OpenSkyRenderCore
import simd

nonisolated public struct DialogueTurn: Equatable, Sendable {
    /// `fDialogueRotationSecs:Dialogue`.
    public static let duration: Float = 1
    /// `fDialogueRotationPitchOffset:Dialogue`, in radians below the aim point.
    public static let pitchOffset: Float = 0.17
    /// `fOutsideDialogueAngleRotationDampen:Controls`.
    public static let dampen: Float = 0.33
    /// `fPCDialogueLookStart:Controls`: a pointer this many points from a window edge
    /// turns the view.
    public static let edgeMargin: Float = 25
    /// `fPCDialogueLookSpeed:Controls`, read as pointer points per 1/60 s.
    public static let edgeSpeed: Float = 10

    /// The soft and hard look stops, in radians, for one kind of camera.
    public struct Stops: Equatable, Sendable {
        public let soft: Float
        public let hard: Float

        /// `fDialogueSoftStopAngle1P` and `fDialogueHardStopAngle1P` in `[Controls]`.
        public static let firstPerson = Stops(soft: 20 * .pi / 180, hard: 45 * .pi / 180)
        /// `fDialogueSoftStopAngle3P` and `fDialogueHardStopAngle3P` in `[Controls]`.
        public static let thirdPerson = Stops(soft: 25 * .pi / 180, hard: 55 * .pi / 180)
    }

    public let startYaw: Float
    public let startPitch: Float
    public private(set) var targetYaw: Float
    public private(set) var targetPitch: Float
    public private(set) var elapsed: Float = 0

    /// The turn from the current view at `eye` to `aim`, the short way round.
    public init(eye: SIMD3<Float>, yaw: Float, pitch: Float, aim: SIMD3<Float>) {
        startYaw = yaw
        startPitch = pitch
        targetYaw = yaw
        targetPitch = pitch
        retarget(eye: eye, aim: aim)
    }

    /// Aims the rest of the turn at `aim`: the speaker's head moves while its pose
    /// settles and while it walks.
    public mutating func retarget(eye: SIMD3<Float>, aim: SIMD3<Float>) {
        let look = aim - eye
        let distance = simd_length(look)
        targetYaw = startYaw + Self.wrapped(atan2f(look.y, look.x) - startYaw)
        let rise = distance > .ulpOfOne ? asinf(min(1, max(-1, look.z / distance))) : 0
        targetPitch = FreeFlyCamera.clampPitch(rise - Self.pitchOffset)
    }

    public var isDone: Bool {
        elapsed >= Self.duration
    }

    /// Moves the turn on by `deltaTime` seconds and gives the view's yaw and pitch, eased
    /// out with `sin(t * pi / 2)`.
    public mutating func advance(by deltaTime: Float) -> (yaw: Float, pitch: Float) {
        elapsed = min(Self.duration, elapsed + max(0, deltaTime))
        let weight = sinf(elapsed / Self.duration * .pi / 2)
        return (
            startYaw + (targetYaw - startYaw) * weight,
            startPitch + (targetPitch - startPitch) * weight
        )
    }

    /// The look a pointer at a window edge adds over `deltaTime`, from the view's centre
    /// toward the pointer: x to the right, y up, in pointer points. `pointer` counts from
    /// the top left of a view of `viewSize`.
    public static func edgeLook(
        pointer: SIMD2<Float>, viewSize: SIMD2<Float>, deltaTime: Float
    ) -> SIMD2<Float> {
        let nearEdge = simd_reduce_min(simd_min(pointer, viewSize - pointer)) < edgeMargin
        let fromCentre = (pointer - viewSize / 2) * SIMD2(1, -1)
        guard nearEdge, simd_length(fromCentre) > 0 else { return .zero }
        return simd_normalize(fromCentre) * edgeSpeed * deltaTime * 60
    }

    /// The speaker's heading from `eye` minus the view's `yaw`; positive is to the left.
    public static func speakerOffset(yaw: Float, eye: SIMD3<Float>, aim: SIMD3<Float>) -> Float {
        wrapped(atan2f(aim.y - eye.y, aim.x - eye.x) - yaw)
    }

    /// The share of a `lookRight` input that turns the view further from a speaker at
    /// `offset`. Turning back toward the speaker is never limited.
    public static func lookScale(lookRight: Float, offset: Float, stops: Stops) -> Float {
        // A positive `lookRight` lowers the yaw, so it turns away when the speaker is to
        // the left, where the offset is positive.
        guard lookRight * offset > 0 else { return 1 }
        let angle = abs(offset)
        if angle <= stops.soft {
            return 1
        }
        if angle > stops.hard {
            return 0
        }
        return dampen * (1 - (angle - stops.soft) / (stops.hard - stops.soft))
    }

    /// `angle` brought into -pi ... pi.
    static func wrapped(_ angle: Float) -> Float {
        var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi {
            value -= 2 * .pi
        }
        if value < -.pi {
            value += 2 * .pi
        }
        return value
    }
}
