// Kill moves from the session: the idle tree picks the paired idle, and a player's kill
// move always shows the kill cam (docs/engine/paired-animations.md#kill-moves).

import OpenSkyActorPresentation
import OpenSkyCamera
import OpenSkyCombat
import OpenSkyFormatsESM

extension CombatWorldAdapter {
    func canBeKilled(_ target: ReferenceKey, by attacker: ReferenceKey) -> Bool {
        game.ragdollWorld.zeroHealthOutcome(of: target, killer: attacker) == .dies
    }

    func startKillMove(_ attempt: KillMoveAttempt) -> Bool {
        guard game.idleWorld.idles.startKillMove(
            attempt.action, attacker: attempt.attacker, target: attempt.target,
            kills: attempt.kills
        ) else { return false }
        if attempt.attacker == .player {
            game.cinematicCamera.playKillCam(
                attacker: .player, target: attempt.target, remainingHostiles: 0, force: true
            )
        }
        return true
    }

    func isInKillMove(_ key: ReferenceKey) -> Bool {
        game.idleWorld.idles.pairedAnimation(of: key)?.isKillMove == true
    }
}
