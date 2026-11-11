// Why the player may not rest now: combat, pursuit, trespass, a falling body, and the
// script and cell locks. The rule is `RestRule`; this reads its facts from the session.

import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension MenuScreensWorldAdapter {
    var rest: Rest {
        Rest(game: game)
    }

    struct Rest {
        let game: any MenuScreensWorldHost

        func restRefusal(sleeping: Bool, bed: FormID?) -> String? {
            var context = RestContext()
            let combat = game.combat.combatLoopSnapshot
            context.inCombat = combat.isPlayerInCombat
            context.hostilesNear = combat.hostileCount > 0
            context.alarmed = game.crime.isPlayerPursued
            context.trespassing = game.crime.isPlayerTrespassing
            context.warnedToLeave = game.crime.isPlayerWarnedToLeave
            if let bed, let key = game.streamer.referenceEntry(formID: bed)?.key {
                // The theft rule decides whose a bed is, as it does for an item.
                context.bedOwnedByOther = game.crime.ownershipVerdict(on: key).isTheft
            }
            context.inAir = !(game.gameSession?.walkController.isGrounded ?? true)
            context.takingHealthDamage = game.magic.isPlayerTakingHealthDamage
            context.waitingDisabled = game.scripts.bridge?.playerControlLocks
                .waitingDisabled ?? false
            context.cellForbidsWaiting = game.streamer.currentCellLocation
                .flatMap { game.streamer.residentScene(at: $0)?.forbidsWaiting } ?? false
            guard let refusal = RestRule.refusal(context) else { return nil }
            return game.mapWorld.settingTexts(RestText.self)[refusal.text(sleeping: sleeping)]
        }
    }
}
