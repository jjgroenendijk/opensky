// App side of the settings, the title menu, the race menu, and the menu
// natives. The rules live in the coordinators in OpenSkyMenus.

public import Foundation
public import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagicInterface
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkySaveInterface
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
    var menuRecords: (any MenuRecordsPort)? { get }
}

public final class MenuWorldAdapter {
    public let game: any MenuWorldHost
    public let state: MenuPartState
    /// Built on first use, because it walks the install.
    public var titleMeshes: MeshLibrary?
    /// The camera the logo was placed for, while the title backdrop shows.
    public var titleLogoView: (eye: SIMD3<Float>, forward: SIMD3<Float>)?

    public let settingsApplyHost: any MenuWorldSettingsApplyHost
    public let skillsRaceHost: any MenuWorldSkillsRaceHost
    public let newGameHost: any MenuWorldNewGameHost
    public let scriptMenusHost: any MenuWorldScriptMenusHost
    public let teleportsHost: any MenuWorldTeleportsHost

    public var settingsApply: MenuWorldSettingsApplyAdapter {
        MenuWorldSettingsApplyAdapter(
            game: settingsApplyHost, state: state
        )
    }

    public var skillsRace: MenuWorldSkillsRaceAdapter {
        MenuWorldSkillsRaceAdapter(
            game: skillsRaceHost, state: state
        )
    }

    public var newGame: MenuWorldNewGameAdapter {
        MenuWorldNewGameAdapter(
            game: newGameHost, state: state, teleports: teleports
        )
    }

    public var scriptMenus: MenuWorldScriptMenusAdapter {
        MenuWorldScriptMenusAdapter(
            game: scriptMenusHost, state: state, skillsRace: skillsRace, teleports: teleports
        )
    }

    public var teleports: MenuWorldTeleportsAdapter {
        MenuWorldTeleportsAdapter(
            game: teleportsHost, state: state
        )
    }

    public init(
        game: some MenuWorldHost & MenuWorldSettingsApplyHost & MenuWorldSkillsRaceHost &
            MenuWorldNewGameHost & MenuWorldScriptMenusHost & MenuWorldTeleportsHost,
        now: @escaping () -> Date
    ) {
        state = MenuPartState(now: now)
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

    public var recordIdentity: PlayerIdentityState? {
        skillsRace.recordIdentity
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
