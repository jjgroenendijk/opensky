// App side of the settings, the title menu, the race menu, and the menu
// natives. The rules live in the coordinators in OpenSkyMenus.

public import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAudio
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagic
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkySave
import OpenSkySaveInterface
import OpenSkyScripting
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol MenuWorldHost: MenuInputConsumer {
    var loadingScreens: any LoadingScreenPort { get }
    var mapWorld: any MapWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var worldData: WorldDataStores? { get }
}

public final class MenuWorldAdapter {
    public unowned let game: any MenuWorldHost
    /// Set by the session scope, because quitting is the app shell's work.
    public var terminateApp: () -> Void = {}
    /// Set by the session scope, which owns the game view that reads the keys.
    public var applyViewBindings: (InputBindings) -> Void = { _ in }
    /// Built on first use, because it walks the install.
    public var titleMeshes: MeshLibrary?
    public var perkSky: PerkSkySource?
    /// The move a new game makes, polled each frame until the player stands.
    public var newGameTeleport: AgentWait?
    /// A chosen test cell opens the race menu when the move ends; a quest's move does not.
    public var raceMenuAfterTeleport = false
    /// The player's race before a script or a magic effect changed it. Not saved.
    public var originalPlayerRace: FormID?
    public var startTickerInstalled = false
    /// The opening quest's player `MoveTo` loads a far cell, so it gets a loading screen.
    public var coverNextTeleport = false
    public var teleportCovered = false
    /// From New until the opening quest moves the player. A dark cover, not the
    /// loading menu, because that menu pauses the scripts that make the move. On the
    /// simulation clock, so a game paused by agent control does not run out the limit.
    public var newGameCoverSince: Double?
    public static let newGameCoverLimitSeconds = 30.0
    /// The camera the logo was placed for, while the title backdrop shows.
    public var titleLogoView: (eye: SIMD3<Float>, forward: SIMD3<Float>)?

    public let settingsApplyHost: any MenuWorldSettingsApplyHost
    public let skillsRaceHost: any MenuWorldSkillsRaceHost
    public let newGameHost: any MenuWorldNewGameHost
    public let scriptMenusHost: any MenuWorldScriptMenusHost
    public let teleportsHost: any MenuWorldTeleportsHost

    public var settingsApply: MenuWorldSettingsApplyAdapter {
        MenuWorldSettingsApplyAdapter(
            owner: self,
            game: settingsApplyHost
        )
    }

    public var skillsRace: MenuWorldSkillsRaceAdapter {
        MenuWorldSkillsRaceAdapter(
            owner: self,
            game: skillsRaceHost
        )
    }

    public var newGame: MenuWorldNewGameAdapter {
        MenuWorldNewGameAdapter(owner: self, game: newGameHost)
    }

    public var scriptMenus: MenuWorldScriptMenusAdapter {
        MenuWorldScriptMenusAdapter(
            owner: self,
            game: scriptMenusHost
        )
    }

    public var teleports: MenuWorldTeleportsAdapter {
        MenuWorldTeleportsAdapter(
            owner: self,
            game: teleportsHost
        )
    }

    public init(game: some MenuWorldHost & MenuWorldSettingsApplyHost & MenuWorldSkillsRaceHost &
        MenuWorldNewGameHost & MenuWorldScriptMenusHost & MenuWorldTeleportsHost)
    {
        settingsApplyHost = game
        skillsRaceHost = game
        newGameHost = game
        scriptMenusHost = game
        teleportsHost = game
        self.game = game
    }

    public var records: MenuRecordData? {
        game.mapWorld.records
    }

    /// The `Player` record's own identity, before the race menu changed it.
    public var recordIdentity: PlayerIdentityState? {
        guard let player = records?.player else { return nil }
        return PlayerIdentityState(
            record: player, details: player.details,
            name: game.mapWorld.text(player.name) ?? "Prisoner"
        )
    }

    /// The name and race shown in the save list.
    public var playerNameAndRace: (name: String, race: String) {
        let identity = playerIdentity
        let race = records?.playableRaces.first { $0.formID == identity?.race }
        return (
            identity?.name ?? "Prisoner",
            game.mapWorld.text(race?.name) ?? race?.editorID ?? ""
        )
    }
}

extension MenuWorldAdapter: PlayerSettingsWorld {}

extension MenuWorldAdapter: RaceMenuWorld, TitleMenuWorld, SkillsMenuWorld {}

extension MenuWorldAdapter: PapyrusMenuBridge {}

extension MenuWorldAdapter {}

extension MenuWorldAdapter: MenuWorldPort {}
