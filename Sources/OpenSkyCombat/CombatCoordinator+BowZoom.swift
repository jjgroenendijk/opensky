// The player's bow zoom against the game data: Eagle Eye's `Mod Bow Zoom` sets the view
// share, its bow `Mod Power Attack Stamina` the drain per second, and Steady Hand's
// `Bow Speed Bonus` the time scale while zoomed. See docs/engine/archery.md.

import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface

extension CombatCoordinator {
    /// What the zoom reads this frame besides the keys.
    func bowZoomConditions(bow: FormID?) -> BowZoomInput {
        let stamina = ActorValueIdentity.index(named: "Stamina")
            .flatMap { world.actorValues(of: .player)?($0) }
        return BowZoomInput(
            viewShare: perkValue(
                1, at: .modBowZoom, on: .player,
                subjects: PerkEvaluationSubjects(owner: .player)
                    .binding(.weapon, to: items?.conditionSubject(of: bow))
            ),
            hasStamina: (stamina ?? 1) >= 1,
            timeIsSlowed: isTimeSlowed
        )
    }

    /// Eagle Eye sets the bow's power attack stamina, and UESP gives the zoom drain as
    /// that much per second.
    func drainBowZoomStamina(bow: FormID?, delta: Float) {
        guard archery?.zoom.isZoomed == true, delta > 0 else { return }
        let perSecond = meleePowerAttackStamina(0, weapon: bow)
        guard perSecond > 0, perSecond.isFinite else { return }
        world.damageStamina(by: perSecond * delta, of: .player)
    }

    /// The world's and the player's share of normal speed: `Bow Speed Bonus` while
    /// zoomed, which Steady Hand lowers, else 1.
    public var bowZoomTimeScale: Float {
        guard
            archery?.zoom.isZoomed == true,
            let bonus = world.actorValues(of: .player)?(ActorValueIndex.bowSpeedBonus),
            bonus.isFinite, bonus > 0
        else { return 1 }
        return min(bonus, 1)
    }
}
