// What an actor's body is doing in a fight, as conditions read it. The combat loop
// fills it for NPCs and the melee graph state for the player.
// See docs/engine/condition-functions-world.md#combat-actions.

import Foundation

/// `GetAttackState` codes, from the Creation Kit wiki page `GetAttackState`.
nonisolated public enum ActorAttackState: Int, Equatable, Sendable {
    case none = 0
    case draw = 1
    case swing = 2
    case hit = 3
    case nextAttack = 4
    case followThrough = 5
    case bash = 6
    case drawingBow = 9
    case holdingBowDrawn = 10
    case loosingArrow = 12

    public var isAttacking: Bool {
        self != .none
    }
}

nonisolated public struct ActorActionFacts: Equatable, Sendable {
    public var attackState: ActorAttackState
    /// The guard is up.
    public var isBlocking: Bool
    /// The actor means to block: its guard is up, or its combat loop chose to block.
    public var wantsBlocking: Bool
    public var isStaggered: Bool
    /// The actor runs from the fight at low health.
    public var isFleeing: Bool
    /// Only the player power attacks. OpenSky has no recoil and no knock-down
    /// outside death, so `isRecoiling` stays false.
    public var isPowerAttacking = false
    public var isRecoiling = false
    /// The editor ID of the attack's type keyword, such as `PowerAttackTypeSide`, which
    /// `IsAttackType` reads. Nil for a plain swing.
    public var attackTypeKeyword: String?

    public init(
        attackState: ActorAttackState = .none,
        isBlocking: Bool = false,
        wantsBlocking: Bool? = nil,
        isStaggered: Bool = false,
        isFleeing: Bool = false
    ) {
        self.attackState = attackState
        self.isBlocking = isBlocking
        self.wantsBlocking = wantsBlocking ?? isBlocking
        self.isStaggered = isStaggered
        self.isFleeing = isFleeing
    }

    /// A dead or idle actor: nothing in progress.
    public static let still = ActorActionFacts()
}
