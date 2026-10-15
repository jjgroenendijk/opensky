// One scripted move of a reference over time, as `TranslateTo` starts it. Pure. Speed is
// units per second and the rotation speed radians per second here. With no rotation cap
// the rotation arrives with the position, and a cap can only slow it
// (<https://ck.uesp.net/wiki/TranslateTo_-_ObjectReference>). See
// docs/engine/papyrus-translation.md.

import Foundation
import OpenSkyWorldState
import simd

nonisolated public struct PapyrusTranslation: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case moving
        /// The first step with `almostCompleteSeconds` or less of travel left.
        case almostComplete
        /// Both the position and the rotation arrived.
        case complete
    }

    /// OpenSky's choice: the wiki names no lead time for `OnTranslationAlmostComplete`.
    public static let almostCompleteSeconds: Float = 0.25

    public private(set) var position: SIMD3<Float>
    /// Euler angles in radians, as `ReferenceTransformOverride` stores them.
    public private(set) var rotation: SIMD3<Float>
    public let targetPosition: SIMD3<Float>
    public let targetRotation: SIMD3<Float>
    public let speed: Float
    /// Zero means no cap.
    public let maxRotationSpeed: Float
    public private(set) var sentAlmostComplete = false

    /// Nil for a speed that is not above zero or a value that is not finite.
    public init?(
        from position: SIMD3<Float>, rotation: SIMD3<Float>,
        to targetPosition: SIMD3<Float>, rotation targetRotation: SIMD3<Float>,
        speed: Float, maxRotationSpeed: Float = 0
    ) {
        let values = [position, rotation, targetPosition, targetRotation]
        guard
            speed.isFinite, speed > 0, maxRotationSpeed.isFinite,
            values.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        else { return nil }
        self.position = position
        self.rotation = rotation
        self.targetPosition = targetPosition
        self.targetRotation = targetRotation
        self.speed = speed
        self.maxRotationSpeed = max(0, maxRotationSpeed)
    }

    public func pose(scale: Float) -> ReferenceTransformOverride {
        ReferenceTransformOverride(position: position, rotation: rotation, scale: scale)
    }

    public var isComplete: Bool {
        position == targetPosition && rotationLeft == .zero
    }

    /// The signed shortest turn left on each axis.
    var rotationLeft: SIMD3<Float> {
        let raw = targetRotation - rotation
        return SIMD3(Self.wrapped(raw.x), Self.wrapped(raw.y), Self.wrapped(raw.z))
    }

    public mutating func advance(by seconds: Float) -> Step {
        guard !isComplete else { return .complete }
        guard seconds.isFinite, seconds > 0 else { return .moving }
        let offset = targetPosition - position
        let distance = simd_length(offset)
        let travel = min(distance, speed * seconds)
        // The share of the remaining path this step covers. Once the position has
        // arrived, only the rotation cap holds the turn back.
        let share: Float = distance > 0 ? travel / distance : 1
        position = travel >= distance ? targetPosition : position + offset * share
        rotation = turned(by: rotationLeft * share, seconds: seconds)
        if isComplete {
            return .complete
        }
        let secondsLeft = simd_length(targetPosition - position) / speed
        guard !sentAlmostComplete, secondsLeft <= Self.almostCompleteSeconds else { return .moving }
        sentAlmostComplete = true
        return .almostComplete
    }

    private func turned(by wanted: SIMD3<Float>, seconds: Float) -> SIMD3<Float> {
        let left = rotationLeft
        var next = rotation
        for axis in 0 ..< 3 {
            var step = wanted[axis]
            if maxRotationSpeed > 0 {
                let cap = maxRotationSpeed * seconds
                step = min(max(step, -cap), cap)
            }
            next[axis] = abs(step) >= abs(left[axis]) ? targetRotation[axis] : rotation[axis] + step
        }
        return next
    }

    /// `angle` in `-pi ... pi`.
    static func wrapped(_ angle: Float) -> Float {
        let turn = 2 * Float.pi
        let folded = (angle + .pi).truncatingRemainder(dividingBy: turn)
        return (folded < 0 ? folded + turn : folded) - .pi
    }
}
