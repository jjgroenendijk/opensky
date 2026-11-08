import Foundation
import OpenSkyGameData

/// One frame of cast intent, filled from the same drained camera input
/// `MeleeIntent` and `ArcheryIntent` are.
nonisolated public struct CastingIntent: Equatable, Sendable {
    /// Block button held, which the left hand takes when it holds a spell.
    public var leftHeld = false
    /// Attack button held, which the right hand takes when it holds a spell.
    public var rightHeld = false
    /// Seconds since the previous frame, for the charge and drain clocks.
    public var deltaTime: Float = 0

    public static let still = CastingIntent()

    public func isHeld(_ hand: SpellHand) -> Bool {
        switch hand {
        case .left: leftHeld
        case .right: rightHeld
        }
    }

    public init(leftHeld: Bool = false, rightHeld: Bool = false, deltaTime: Float = 0) {
        self.leftHeld = leftHeld
        self.rightHeld = rightHeld
        self.deltaTime = deltaTime
    }
}
