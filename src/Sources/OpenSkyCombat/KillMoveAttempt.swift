// The kill rule a swing's kill move tests: `ShouldAttackKill`.
// See docs/engine/paired-animations.md#kill-moves.

import OpenSkyCombatInterface
public import OpenSkyFormatsESM

/// One attack that may play a kill move: the idle tree under `action` tests `kills`.
nonisolated public struct KillMoveAttempt: Equatable, Sendable {
    public static let attackAction = "ActionRightAttack"
    static let powerAttackAction = "ActionRightPowerAttack"
    /// An actor in a kill move takes ten times the damage of any other hit.
    public static let damageMultiplier: Float = 10

    public let attacker: ReferenceKey
    public let target: ReferenceKey
    public let action: String
    public let kills: Bool

    public init(attacker: ReferenceKey, target: ReferenceKey, action: String, kills: Bool) {
        self.attacker = attacker
        self.target = target
        self.action = action
        self.kills = kills
    }
}
