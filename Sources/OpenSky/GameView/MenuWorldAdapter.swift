// App side of the settings, the title menu, the race menu, and the menu
// natives. The rules live in the coordinators in OpenSkyMenus.

import AppKit
import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyRendering
import OpenSkySave
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState

final class MenuWorldAdapter {
    unowned let game: GameViewController
    /// Built on first use, because it walks the install.
    var titleMeshes: MeshLibrary?
    /// The move a new game makes, polled each frame until the player stands.
    var newGameTeleport: AgentWait?
    /// A chosen test cell opens the race menu when the move ends; a quest's move does not.
    private var raceMenuAfterTeleport = false
    private var startTickerInstalled = false
    /// The opening quest's player `MoveTo` loads a far cell, so it gets a loading screen.
    private var coverNextTeleport = false
    private var teleportCovered = false
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
        game.subtitles.settings = hud.subtitles
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

    func racePresets(race: FormID, isFemale: Bool) -> [RacePreset] {
        guard let record = records?.playableRaces.first(where: { $0.formID == race }) else {
            return []
        }
        let head = isFemale ? record.details.headData.female : record.details.headData.male
        return head.presets.compactMap { preset in
            guard let npc = identityRecords?.templates.actors[preset.rawValue] else { return nil }
            let name = npc.editorID ?? "\(preset)"
            return RacePreset(
                name: name,
                face: PlayerIdentityState(record: npc, details: npc.details, name: name).face
            )
        }
    }

    func raceMenuClosed() {
        game.scripts.runtime?.queueRaceSwitchComplete(actor: .player)
    }

    /// A fresh session: empty world state, the start clock, and the opening
    /// quests. The opening quest places the player and opens the race menu itself.
    /// A chosen cell is a test start, so the race menu opens there at once.
    func startNewGame(at start: NewGameStart) {
        game.worldState.restore(from: .empty)
        game.renderer?.gameClock = GameClock()
        game.scripts.restore(instances: [], timers: [])
        game.messages.reloadHelpRecords()
        game.storyWorld.rerunSessionStart()
        game.saveGames.resetPlayTime()
        game.player.refreshBody()
        switch start {
        case .vanilla:
            coverNextTeleport = true
            game.storyWorld.startOpeningQuest()
        case let .cell(editorID): teleportPlayer(.cell(editorID), openingRaceMenu: true)
        }
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
        if actor == .player {
            return playerIdentity?.race
        }
        return game.scripts.bridge?.placedReference(for: actor)
            .flatMap { identityRecords?.race(ofBase: $0.base) }
    }

    func sex(ofBase base: FormID) -> Int? {
        let isFemale = base == MenuRecordData.playerBase
            ? playerIdentity?.isFemale : identityRecords?.isFemale(ofBase: base)
        return isFemale.map { $0 ? 1 : 0 }
    }

    func name(of form: FormID) -> String? {
        if form == MenuRecordData.playerBase {
            return playerIdentity?.name
        }
        return game.mapWorld.text(identityRecords?.name(of: form))
    }

    /// Only `Skyrim.esm` references, because the lookup outside the loaded cells
    /// reads that file.
    func movePlayer(to target: ReferenceKey) {
        guard case let .plugin(name, objectID) = target, name == "skyrim.esm" else {
            game.hud.showNotification("MoveTo: \(target) is not in Skyrim.esm")
            return
        }
        teleportPlayer(.reference(String(format: "0x%06X", objectID)), openingRaceMenu: false)
    }

    private var identityRecords: ActorIdentityRecords? {
        (game.worldData as? ActorValueDataProviding)?.actorValueBaselines?.resolver
            .map(ActorIdentityRecords.init(resolver:))
    }
}

extension MenuWorldAdapter {
    /// Moves the player the way `debug.teleport` does.
    func teleportPlayer(_ target: AgentTeleportTarget, openingRaceMenu: Bool) {
        movePlayer(openingRaceMenu: openingRaceMenu) { [game] () throws(AgentFailure) in
            try AgentTeleportJob(adapter: game.agentWorld, target: target)
        }
    }

    /// A load puts the player back where the save was made, behind the loading screen.
    func restorePlayerPlace(_ place: SavePlayerPlace) {
        coverNextTeleport = true
        movePlayer(openingRaceMenu: false) { [game] () throws(AgentFailure) in
            try AgentTeleportJob(adapter: game.agentWorld, place: place)
        }
    }

    private func movePlayer(
        openingRaceMenu: Bool,
        job: () throws(AgentFailure) -> AgentTeleportJob
    ) {
        raceMenuAfterTeleport = openingRaceMenu
        if coverNextTeleport {
            coverNextTeleport = false
            teleportCovered = true
            game.loadingScreens.beginLoad(at: Date().timeIntervalSinceReferenceDate)
        }
        do {
            newGameTeleport = try job().wait
        } catch {
            game.hud.showNotification("Move: \(error.message)")
            liftTeleportCover(at: Date().timeIntervalSinceReferenceDate)
            openRaceMenuIfAsked()
            return
        }
        guard !startTickerInstalled, let renderer = game.renderer else { return }
        startTickerInstalled = true
        renderer.onFrame.add { [weak self] _ in
            self?.pollNewGameTeleport(now: Date().timeIntervalSinceReferenceDate)
        }
    }

    private func pollNewGameTeleport(now: Double) {
        guard let wait = newGameTeleport else { return }
        guard let result = wait.poll(now).finish else { return }
        newGameTeleport = nil
        if case let .failure(error) = result {
            game.hud.showNotification("Move: \(error.message)")
        }
        liftTeleportCover(at: now)
        openRaceMenuIfAsked()
    }

    /// A new or loaded game is played, so the player walks rather than flies.
    private func liftTeleportCover(at now: Double) {
        guard teleportCovered else { return }
        teleportCovered = false
        game.loadingScreens.loadFinished(at: now)
        game.renderer?.setMovementMode(.walk)
    }

    private func openRaceMenuIfAsked() {
        guard raceMenuAfterTeleport else { return }
        raceMenuAfterTeleport = false
        game.raceMenu.open(limited: false)
    }
}
