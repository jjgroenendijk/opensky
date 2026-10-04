// App side of the settings, the title menu, the race menu, and the menu
// natives. The rules live in the coordinators in OpenSkyMenus.

import AppKit
import OpenSkyActorsInterface
import OpenSkyAudio
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState

final class MenuWorldAdapter {
    unowned let game: GameViewController
    /// Built on first use, because it walks the install.
    var titleMeshes: MeshLibrary?
    /// The camera the logo was placed for, while the title backdrop shows.
    var titleLogoView: (eye: SIMD3<Float>, forward: SIMD3<Float>)?

    init(game: GameViewController) {
        self.game = game
    }

    private var records: MenuRecordData? {
        game.mapWorld.records
    }

    /// The `Player` record's own identity, before the race menu changed it.
    var recordIdentity: PlayerIdentityState? {
        guard let player = records?.player else { return nil }
        return PlayerIdentityState(
            record: player, details: player.details,
            name: game.mapWorld.text(player.name) ?? "Prisoner"
        )
    }

    /// The name and race shown in the save list.
    var playerNameAndRace: (name: String, race: String) {
        let identity = playerIdentity
        let race = records?.playableRaces.first { $0.formID == identity?.race }
        return (
            identity?.name ?? "Prisoner",
            game.mapWorld.text(race?.name) ?? race?.editorID ?? ""
        )
    }
}

extension MenuWorldAdapter: PlayerSettingsWorld {
    func applyMasterVolume(_ volume: Float) {
        game.audio.audioMasterVolume = volume
    }

    func applyCategoryVolume(_ volume: Float, soundCategoryEditorID: String) {
        guard
            let category = AudioCategory.allCases.first(where: {
                $0.soundCategoryEditorID == soundCategoryEditorID
            }) else { return }
        game.audio.setAudioVolume(volume, for: category)
    }

    func applyLook(sensitivity: Float, inverted: Bool) {
        game.cameraInput.lookScale = sensitivity
        game.cameraInput.invertLook = inverted
    }

    func applyHUD(_ hud: PlayerHUDSettings) {
        game.hud.update {
            $0.crosshairEnabled = hud.crosshair
            $0.compassEnabled = hud.compass
            $0.markersEnabled = hud.floatingMarkers
        }
        game.renderer?.swfOpacity = hud.opacity
    }

    func applyDifficulty(index: Int) {
        game.combat.difficulty = DifficultyLevel(index: index)
    }

    func applyBindings(_ bindings: InputBindings) {
        (game.view as? GameMetalView)?.bindings = bindings
    }
}

extension MenuWorldAdapter: RaceMenuWorld, TitleMenuWorld {
    var menuInputConsumer: (any MenuInputConsumer)? {
        game
    }

    var renderer: Renderer? {
        game.renderer
    }

    var playerIdentity: PlayerIdentityState? {
        game.worldState.component(PlayerIdentityState.self, for: .player) ?? recordIdentity
    }

    var playableRaces: [RaceChoice] {
        (records?.playableRaces ?? []).map {
            RaceChoice(
                formID: $0.formID,
                name: game.mapWorld.text($0.name) ?? $0.editorID ?? "\($0.formID)"
            )
        }
    }

    func applyPlayerIdentity(_ identity: PlayerIdentityState) {
        game.worldState.set(identity, for: .player)
        game.player.refreshBody()
    }

    func raceMenuClosed() {
        game.scripts.runtime?.queueRaceSwitchComplete(actor: .player)
    }

    /// A fresh session: empty world state, the start clock, the opening quests,
    /// then the race menu, as the opening quest would show it.
    func startNewGame() {
        game.worldState.restore(from: .empty)
        game.renderer?.gameClock = GameClock()
        game.scripts.restore(instances: [], timers: [])
        game.messages.reloadHelpRecords()
        game.storyWorld.rerunSessionStart()
        game.saveGames.resetPlayTime()
        game.player.refreshBody()
        game.raceMenu.open(limited: false)
    }

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}

extension MenuWorldAdapter: PapyrusMenuBridge {
    func showRaceMenu(limited: Bool) {
        game.raceMenu.open(limited: limited)
    }

    func fastTravel(to marker: ReferenceKey) -> Bool {
        guard game.mapMenu.select(key: marker) else { return false }
        game.mapMenu.travelToSelected()
        return true
    }

    func setFastTravelEnabled(_ enabled: Bool) {
        game.mapMenu.fastTravelEnabled = enabled
    }

    func addToMap(_ marker: ReferenceKey, allowFastTravel: Bool) {
        game.mapMenu.addToMap(marker, allowFastTravel: allowFastTravel)
    }

    func isMapMarkerVisible(_ marker: ReferenceKey) -> Bool {
        game.mapMenu.isVisible(marker)
    }

    func race(of actor: ReferenceKey) -> FormID? {
        actor == .player ? playerIdentity?.race : nil
    }

    func sex(ofBase base: FormID) -> Int? {
        guard base == MenuRecordData.playerBase, let identity = playerIdentity else { return nil }
        return identity.isFemale ? 1 : 0
    }

    func name(of form: FormID) -> String? {
        form == MenuRecordData.playerBase ? playerIdentity?.name : nil
    }
}
