// A `TranslateTo` move that runs when the game saves. A load goes on with it from the
// same pose (docs/engine/papyrus-translation.md#a-move-in-a-save).

import Foundation
public import OpenSkyWorldState

nonisolated public struct SavedTranslation: WorldStateComponent, Sendable {
    /// Where the reference is drawn now, and its Euler angles in radians.
    public let position: SIMD3<Float>
    public let rotation: SIMD3<Float>
    public let targetPosition: SIMD3<Float>
    public let targetRotation: SIMD3<Float>
    /// Units per second.
    public let speed: Float
    /// Radians per second; zero means no cap.
    public let maxRotationSpeed: Float
    /// `OnTranslationAlmostComplete` was already sent.
    public let sentAlmostComplete: Bool

    public static var componentKind: WorldStateComponentKind {
        .savedTranslation
    }

    public init(
        position: SIMD3<Float>, rotation: SIMD3<Float>,
        targetPosition: SIMD3<Float>, targetRotation: SIMD3<Float>,
        speed: Float, maxRotationSpeed: Float, sentAlmostComplete: Bool
    ) {
        self.position = position
        self.rotation = rotation
        self.targetPosition = targetPosition
        self.targetRotation = targetRotation
        self.speed = speed
        self.maxRotationSpeed = maxRotationSpeed
        self.sentAlmostComplete = sentAlmostComplete
    }
}

nonisolated extension WorldStateComponentKind {
    /// A running scripted move. Keyed by the moving reference. A cell build does not
    /// read it: the renderer draws the move from the published poses.
    static let savedTranslation = Self(
        rawValue: "savedTranslation", order: 50, affectsCellBuild: false
    )
}
