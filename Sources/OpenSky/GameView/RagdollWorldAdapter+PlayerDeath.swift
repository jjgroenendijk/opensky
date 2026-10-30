// The app side of the player's death: the messages, the reload of the newest save,
// and the choice when there is none (docs/engine/ragdoll.md#player-death).

import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyScripting
import OpenSkyScriptingInterface

extension RagdollWorldAdapter {
    func advancePlayerDeath(delta: Float) {
        guard let share = healthFraction(of: .player) else { return }
        let sample = PlayerHealthSample(
            share: share, isEssential: isPlayerEssential,
            bleedoutRatio: bleedoutThreshold(of: .player)
        )
        if game.ragdoll.playerDeath.isBleedingOut {
            let regen = game.ragdoll.deathSettings.bleedoutRegenPercent / 100 * max(delta, 0)
            restoreHealthShare(regen, of: .player)
        }
        for command in game.ragdoll.playerDeath.advance(by: delta, health: sample) {
            run(command)
        }
    }

    /// A script's `SetEssential` on the player's base, `Player` (0x7).
    private var isPlayerEssential: Bool {
        guard
            let bridge = game.scripts.bridge,
            let base = bridge.referenceKey(forFormID: MenuRecordData.playerBase)
        else { return false }
        return bridge.scriptedState(of: base).flag(ScriptedStateName.essential) == true
    }

    private var deathTexts: GameSettingTexts<PlayerDeathText> {
        game.mapWorld.settingTexts(PlayerDeathText.self)
    }

    private func run(_ command: PlayerDeathCommand) {
        switch command {
        case .enterBleedout:
            game.hud.showNotification(deathTexts[.bleedingOut])
            game.scripts.runtime?.queueEnterBleedout(actor: .player)
        case let .leaveBleedout(restoreHealth):
            if restoreHealth {
                restoreHealthShare(1, of: .player)
            }
        case .die:
            _ = game.scripts.bridge?.stopActorCombat(.player)
            game.hud.showNotification(deathTexts[.reloading])
        case .reloadNewestSave:
            reloadNewestSave()
        }
    }

    /// With no save, the player picks between loading again and the main menu.
    private func reloadNewestSave() {
        let newest = game.saveGames.saveRows.filter { !$0.isImport }
            .max { $0.savedAt < $1.savedAt }
        if let newest {
            game.titleMenu.load(newest.slot)
            return
        }
        let texts = deathTexts
        game.messages.presentChoices(
            title: nil, text: texts[.reloading],
            buttons: [texts[.loadOption], texts[.menuOption]]
        ) { [weak self] index in
            guard let self else { return }
            if index == 0 {
                reloadNewestSave()
            } else {
                game.ragdoll.playerDeath.reset()
                game.quitToMainMenu()
            }
        }
    }
}
