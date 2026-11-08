// The kill rule a swing's kill move tests: `ShouldAttackKill`.
// See docs/engine/paired-animations.md#kill-moves.

import OpenSkyCombatInterface
public import OpenSkyFormatsESM

/// One attack that may play a kill move: the idle tree under `action` tests `kills`.
nonisolated public struct KillMoveAttempt: Equatable, Sendable {
    public static let attackAction = "ActionRightAttack"
    public static let powerAttackAction = "ActionRightPowerAttack"
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

extension CombatCoordinator {
    /// The attack kills when its hit, after difficulty, takes the target's health to zero
    /// and zero health kills the target.
    @discardableResult
    public func startMeleeKillMove(on target: ReferenceKey, damage: Float, power: Bool) -> Bool {
        let attacker = meleeAttacker.key
        return world.startKillMove(KillMoveAttempt(
            attacker: attacker,
            target: target,
            action: power ? KillMoveAttempt.powerAttackAction : KillMoveAttempt.attackAction,
            kills: attackKills(target, damage: damage, attacker: attacker)
        ))
    }

    /// An NPC's kill move. The player's own death has its own camera, so an NPC kill
    /// move takes only another NPC.
    public func startCombatKillMove(
        by actor: ReferenceKey, on target: ReferenceKey, damage: Float
    ) -> Bool {
        guard target != .player else { return false }
        return world.startKillMove(KillMoveAttempt(
            attacker: actor, target: target, action: KillMoveAttempt.attackAction,
            kills: attackKills(target, damage: damage, attacker: actor)
        ))
    }

    func attackKills(_ target: ReferenceKey, damage: Float, attacker: ReferenceKey) -> Bool {
        guard let health = world.health(of: target), health.current > 0, damage > 0 else {
            return false
        }
        let scaled = DifficultyDamage.scaled(
            damage, attackerIsPlayer: attacker == .player, targetIsPlayer: target == .player,
            multipliers: difficultyMultipliers
        )
        return health.current - scaled <= 0 && world.canBeKilled(target, by: attacker)
    }
}
