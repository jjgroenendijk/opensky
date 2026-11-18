// The kill rule a swing's kill move tests: `ShouldAttackKill`.
// See docs/engine/paired-animations.md#kill-moves.

import OpenSkyCombatInterface
public import OpenSkyFormatsESM

/// One attack that may play a kill move: the idle tree under `action` tests `kills`.
nonisolated public struct KillMoveAttempt: Equatable, Sendable {
    public static let attackAction = "ActionRightAttack"
    static let powerAttackAction = "ActionRightPowerAttack"

    /// The AACT action whose idle tree holds the kill moves of a strike with `hand`.
    static func action(hand: MeleeStrikeHand, power: Bool) -> String {
        switch (hand, power) {
        case (.right, false): attackAction
        case (.right, true): powerAttackAction
        case (.left, false): "ActionLeftAttack"
        case (.left, true): "ActionLeftPowerAttack"
        case (.dual, false): "ActionDualAttack"
        case (.dual, true): "ActionDualPowerAttack"
        }
    }

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
