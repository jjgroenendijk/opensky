import Foundation
import OpenSkyBehavior
import simd

/// What an actor's movement drive does, as the graph's locomotion inputs see it.
nonisolated public struct ActorGraphMotion: Equatable, Sendable {
    public var isMoving: Bool
    public var isSprinting: Bool
    public var isSneaking: Bool
    /// The horse graphs' `iCombatStance`: the actor, or its rider, has a weapon out.
    public var isInCombatStance: Bool

    public static let still = ActorGraphMotion()
    /// Slower than this, in units per second, a driven actor counts as standing.
    public static let movingSpeed: Float = 0.5

    public init(
        isMoving: Bool = false,
        isSprinting: Bool = false, isSneaking: Bool = false, isInCombatStance: Bool = false
    ) {
        self.isMoving = isMoving
        self.isSprinting = isSprinting
        self.isSneaking = isSneaking
        self.isInCombatStance = isInCombatStance
    }
}
