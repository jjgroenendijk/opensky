import OpenSkyAudio
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyRenderCore
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld

/// What `RagdollPlayerFallAdapter` reads from the session.
@MainActor
public protocol RagdollPlayerFallHost: AnyObject {
    var audio: any AudioPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var hud: any HUDPort { get }
    var mapWorld: any MapWorldPort { get }
    var messages: any MessageCoordinatorPort { get }
    func quitToMainMenu()
    var ragdoll: any RagdollPort { get }
    var saveGames: any SaveGameWorldPort { get }
    var scripts: any ScriptPort { get }
    var titleMenu: any TitleMenuPort { get }
}

/// Part of `RagdollWorldAdapter`, over its own narrow host.
public struct RagdollPlayerFallAdapter {
    public unowned let owner: RagdollWorldAdapter
    public unowned let game: any RagdollPlayerFallHost
}

extension RagdollPlayerFallAdapter {
    public func advancePlayerDeath(delta: Float) {
        guard let share = owner.healthFraction(of: .player) else { return }
        let sample = PlayerHealthSample(
            share: share, isEssential: isPlayerEssential,
            bleedoutRatio: owner.bleedoutThreshold(of: .player)
        )
        if game.ragdoll.playerDeath.isBleedingOut {
            let regen = game.ragdoll.deathSettings.bleedoutRegenPercent / 100 * max(delta, 0)
            owner.restoreHealthShare(regen, of: .player)
        }
        for command in game.ragdoll.advancePlayerDeath(by: delta, health: sample) {
            run(command)
        }
    }

    /// A script's `SetEssential` on the player's base, `Player` (0x7), or a quest alias.
    private var isPlayerEssential: Bool {
        game.scripts.bridge?.actorFlags(of: .player)?.contains(.essential) == true
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
                owner.restoreHealthShare(1, of: .player)
            }
        case .die:
            _ = game.scripts.bridge?.stopActorCombat(.player)
            showPlayerFall()
            game.audio.musicDirector?.playSpecialMusic(.death)
            game.hud.showNotification(deathTexts[.reloading])
        case .reloadNewestSave:
            reloadNewestSave()
        }
    }

    /// The body falls as a ragdoll. A first-person eye sits inside the head, so the
    /// view steps out to third person to show it.
    private func showPlayerFall() {
        if game.gameSession?.movementMode == .walk {
            game.gameSession?.setMovementMode(.thirdPerson)
        }
        game.ragdoll.dropPlayerBody()
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
        ) { [weak owner] index in
            guard owner != nil else { return }
            if index == 0 {
                reloadNewestSave()
            } else {
                game.ragdoll.resetPlayerDeath()
                game.quitToMainMenu()
            }
        }
    }
}
