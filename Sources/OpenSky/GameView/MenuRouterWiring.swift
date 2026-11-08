// Connects the settings, menu text, sounds, and frame tick that every menu movie shares.

import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface

/// Settings, key bindings, menu text, the menu natives, map discovery, and the menu
/// movies' late calls.
struct MenuRouterWiring {
    init(_ router: MenuRouter, gameSession: GameSession) {
        let game = router.game
        let renderer = gameSession.renderer
        game.playerSettings.loadControlMap(try? game.controlMapLoader?())
        game.playerSettings.applyAll()
        game.audio.engineStarted
            .register(.playerSettings) { [weak game] _ in game?.playerSettings.applyAll() }
        if let labels = game.menuTextLoader?() {
            renderer.swfTextTranslator = { labels.label(for: $0) }
        }
        router.monitor.onDisconnect = { [weak game] in
            guard let game else { return }
            let texts = game.mapWorld.settingTexts(GamepadNoticeText.self)
            game.messages.presentChoices(
                title: texts[.title], text: texts[.message], buttons: [texts[.confirm]]
            ) { _ in }
        }
        let sounds = MenuSoundPlayer(MenuSoundDependencies(game: game))
        renderer.swfSoundPlayer = { sounds.play(editorID: $0 ?? MenuSoundPlayer.okSound) }
        let ticks = router.ticks
        let monitor = router.monitor
        gameSession.frameSteps.register(.menuRouting) { [ticks, weak renderer, monitor] _ in
            ticks.tick(renderer: renderer, monitor: monitor)
        }
    }
}
