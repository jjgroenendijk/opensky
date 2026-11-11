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
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagicInterface
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySaveInterface
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol MenuWorldHost: MenuInputConsumer, SendableMetatype {
    var loadingScreens: any LoadingScreenPort { get }
    var mapWorld: any MapWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var menuRecords: (any MenuRecordsPort)? { get }
}

/// Every host a `MenuWorldAdapter` part reads, all one object.
public typealias MenuWorldHosts = MenuWorldHost & MenuWorldNewGameHost & MenuWorldScriptMenusHost &
    MenuWorldSettingsApplyHost &
    MenuWorldSkillsRaceHost &
    MenuWorldTeleportsHost

public final class MenuWorldAdapter {
    public let game: any MenuWorldHost
    public let state: MenuPartState
    lazy var titleBackdrop = MenuTitleBackdrop(game: game)

    let hosts: any MenuWorldHosts

    public var settingsApply: MenuWorldSettingsApplyAdapter {
        MenuWorldSettingsApplyAdapter(
            game: hosts, state: state
        )
    }

    public var skillsRace: MenuWorldSkillsRaceAdapter {
        MenuWorldSkillsRaceAdapter(
            game: hosts, state: state
        )
    }

    public var newGame: MenuWorldNewGameAdapter {
        MenuWorldNewGameAdapter(
            game: hosts, state: state, teleports: teleports
        )
    }

    public var scriptMenus: MenuWorldScriptMenusAdapter {
        MenuWorldScriptMenusAdapter(
            game: hosts, state: state, skillsRace: skillsRace, teleports: teleports
        )
    }

    public var teleports: MenuWorldTeleportsAdapter {
        MenuWorldTeleportsAdapter(
            game: hosts, state: state
        )
    }

    public init(
        game: some MenuWorldHosts,
        now: @escaping () -> Date
    ) {
        state = MenuPartState(now: now)
        hosts = game
        self.game = game
    }

    var records: MenuRecordData? {
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
