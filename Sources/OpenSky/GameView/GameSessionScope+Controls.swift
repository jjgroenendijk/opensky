// The player's locked controls, from the scripts and the beast form, and the game's text
// when the player presses a locked one. See docs/engine/papyrus-script-state.md#player-controls.

import OpenSkyCombat
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyScripting
import OpenSkyScriptingInterface

extension GameSessionScope {
    var playerControlLocks: PlayerControlLocks {
        var locks = scripts.bridge?.playerControlLocks ?? .none
        locks.isBeastForm = playerBeastForm.isBeast
        let death = ragdoll.playerDeath
        if death.isDead {
            locks.disabled = Set(PlayerControlGroup.allCases)
        } else if death.isBleedingOut {
            locks.disabled.formUnion([.movement, .fighting, .sneaking, .activate])
        }
        return locks
    }

    func showControlRefusal(_ refusal: PlayerControlRefusal) {
        let texts = mapWorld.settingTexts(ControlRefusalText.self)
        let text: String? = switch refusal {
        case .silent: nil
        case .menusDisabled: texts[.menusDisabled]
        case .chargenControls: texts[.chargenControls]
        case .quickSaveWhilePaused: saveGames.saveTexts.cannotQuickSave
        case .quickLoadWhilePaused: saveGames.saveTexts.cannotQuickLoad
        }
        if let text {
            hud.showNotification(text)
        }
    }
}
