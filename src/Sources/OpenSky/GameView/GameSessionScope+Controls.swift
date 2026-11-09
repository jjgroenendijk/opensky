// The player's locked controls, from the scripts and the beast form, and the game's text
// when the player presses a locked one. See docs/engine/papyrus-script-state.md#player-controls.

import OpenSkyActorAdapters
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyObjectAnimation
import OpenSkyPlayer
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionAdapters
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension GameSessionScope {
    var playerControlLocks: PlayerControlLocks {
        var locks = scripts.bridge?.playerControlLocks ?? .none
        locks.isBeastForm = playerBeastForm.isBeast
        let death = ragdoll.playerDeath
        if death.isDead {
            locks.disabled = Set(PlayerControlGroup.allCases)
        } else if death.isBleedingOut || ragdoll.knockdowns.isKnockedDown(.player) {
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

extension GameSessionScope {
    /// The quest notices the HUD shows each frame the quest state changed.
    func updateQuestNotices() {
        guard let runtime = journal.runtime else { return }
        questNotices.update(
            runtime: runtime, quests: runtime.runtimeQuests(),
            revision: runtime.store.revision(of: [.quest]),
            strings: journal.strings, aliases: journalMenu.aliasNaming(runtime: runtime)
        )
    }

    /// The camera that world billboards and effect billboards turn to.
    var billboardViewer: NIFBillboard.Viewer? {
        gameSession.map { NIFBillboard.Viewer(camera: $0.freeFlyCamera) }
    }
}

extension GameSessionScope {
    var playerBeastForm: PlayerBeastForm {
        beastForms.form
    }
}
