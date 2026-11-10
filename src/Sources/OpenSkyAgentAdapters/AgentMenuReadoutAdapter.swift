import Foundation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMenusInterface
import OpenSkyObjectAnimation
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `AgentMenuReadoutAdapter` reads from the session.
@MainActor
public protocol AgentMenuReadoutHost: AnyObject, SendableMetatype {
    var containerMenu: any ContainerMenuPort { get }
    var dialogueMenu: any DialogueMenuPort { get }
    var inventoryMenu: any InventoryMenuPort { get }
    var journalMenu: any JournalMenuPort { get }
    var menuMode: any MenuModePort { get }
    var messages: any MessageCoordinatorPort { get }
    var progression: any ProgressionPort { get }
    var raceMenu: any RaceMenuPort { get }
    var skillsMenu: any SkillsMenuPort { get }
    var systemMenu: any SystemMenuPort { get }
    var titleMenu: any TitleMenuPort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentMenuReadoutAdapter {
    let hub: AgentHub
    public let game: any AgentMenuReadoutHost
}

extension AgentMenuReadoutAdapter {
    /// Nil when no menu is open or the top menu has no row list.
    public func menuRows() -> AgentMenuRows? {
        guard let top = game.menuMode.topMenu else { return nil }
        switch top {
        case .inventoryMenu:
            let snapshot = game.inventoryMenu.snapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.entryLines,
                selected: snapshot.selectedIndex
            )
        case .containerMenu, .barterMenu:
            let snapshot = game.containerMenu.snapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.entryLines,
                selected: snapshot.selectedIndex
            )
        case .journalMenu:
            let snapshot = game.journalMenu.snapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.rows.map(\.title),
                selected: snapshot.selectedIndex
            )
        case .dialogueMenu:
            let snapshot = game.dialogueMenu.snapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.rows.map(\.text),
                selected: snapshot.selectedIndex
            )
        case MenuIdentifier.titleMenu:
            return titleMenuRows(top)
        case MenuIdentifier.systemMenu:
            let menu = game.systemMenu
            let page = menu.movieMainPage ?? menu.snapshot.page
            return AgentMenuRows(menu: top.name, rows: page.rows, selected: page.selectedIndex)
        case MenuIdentifier.raceMenu:
            let snapshot = game.raceMenu.snapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.rows,
                selected: snapshot.selectedIndex
            )
        case MenuIdentifier.statsMenu:
            let snapshot = game.skillsMenu.snapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.rows,
                selected: snapshot.selectedIndex ?? -1
            )
        case MenuIdentifier.messageBoxMenu:
            guard let box = game.messages.presentation else { return nil }
            return AgentMenuRows(
                menu: top.name,
                rows: box.request.buttons.map(\.text),
                selected: box.selection
            )
        default:
            return nil
        }
    }

    private func titleMenuRows(_ top: MenuIdentifier) -> AgentMenuRows {
        let snapshot = game.titleMenu.snapshot
        guard snapshot.movie.isLoaded, !snapshot.isLoadPageOpen else {
            return AgentMenuRows(
                menu: top.name, rows: snapshot.rows, selected: snapshot.selectedIndex
            )
        }
        return AgentMenuRows(
            menu: top.name,
            rows: snapshot.movie.rows,
            selected: snapshot.movie.selectedIndex ?? -1
        )
    }

    public var menuState: AgentJSON {
        var result: [String: AgentJSON] = [
            "open": .array(game.menuMode.stack.identifiers.map { .string($0.name) }),
            "top": .init(game.menuMode.topMenu?.name),
            "worldPaused": .bool(game.menuMode.isWorldSimPaused),
            "hud": hub.screens.hudState,
            "loading": hub.screens.loadingState,
            "movie": hub.screens.movieFocusState,
            "bink": hub.screens.binkState,
            "titles": hub.screens.titlesState,
            "map": hub.screens.mapState
        ]
        if let rows = menuRows() {
            result["rows"] = .array(rows.rows.map { .string($0) })
            result["selected"] = .init(rows.selected)
        }
        if game.menuMode.topMenu == MenuIdentifier.statsMenu {
            result["skills"] = skillsMenuState(game.skillsMenu.snapshot)
        }
        if game.systemMenu.isOpen {
            result["systemPage"] = .string(game.systemMenu.model.page.rawValue)
            result["topic"] = .init(game.systemMenu.topicPage?.openTopic?.title)
            if let movie = game.systemMenu.movieDiagnostics {
                result["systemMovie"] = [
                    "state": movie.state.map { .init($0) } ?? .null, "faults": .init(movie.faults),
                    "missing": .array(movie.missingNames.map { .string($0) })
                ]
            }
        }
        if game.titleMenu.isOpen {
            result["credits"] = .bool(game.titleMenu.creditsShown)
        }
        return .object(result)
    }

    /// The page, the movies, and the perk sky line, such as "812 draws, turned 40°, ring".
    func skillsMenuState(_ snapshot: SkillsMenuSnapshot) -> AgentJSON {
        [
            "page": .string(snapshot.page),
            "movie": .init(snapshot.movie.state),
            "movieLoaded": .bool(snapshot.movie.isLoaded),
            "movieError": .init(snapshot.movie.error),
            "levelUpMovie": .bool(snapshot.isLevelUpMovieLoaded),
            "skyEnabled": .bool(snapshot.isSkyEnabled),
            "sky": .init(snapshot.sky)
        ]
    }

    func openRaceMenu(limited: Bool) throws(AgentFailure) -> AgentJSON {
        guard game.raceMenu.isOpen || game.raceMenu.open(limited: limited) else {
            throw AgentFailure(.notReady, "the race menu needs a loaded world")
        }
        return ["open": true, "limited": .bool(game.raceMenu.snapshot.isLimited)]
    }

    func openSkillsMenu(sky: Bool?, levels: Int) throws(AgentFailure) -> AgentJSON {
        let menu = game.skillsMenu
        if let sky {
            menu.setSkyEnabled(sky)
        }
        if levels > 0 {
            guard menu.model == nil, let leveling = game.progression.leveling else {
                throw AgentFailure(.notReady, "levels are earned before the menu opens")
            }
            for _ in 0 ..< levels {
                let missing = leveling.experienceForNextLevel - leveling.state.experience
                game.progression.awardCharacterExperience(max(1, missing))
                game.progression.applyEarnedLevels()
            }
        }
        guard menu.model != nil || menu.open() else {
            throw AgentFailure(.notReady, "the skills menu needs a loaded world")
        }
        return skillsMenuState(menu.snapshot)
    }

    public func questState(_ editorID: String) throws(AgentFailure) -> AgentJSON {
        guard let quests = game.journalMenu.questRuntime else {
            throw AgentFailure(.notReady, "no quest data is loaded")
        }
        guard let state = attempt({ try quests.state(editorID: editorID) }) else {
            throw AgentFailure(.notFound, "no quest '\(editorID)'")
        }
        return [
            "id": .string(editorID),
            "stage": state.stagesReached.last.map { .init(Int($0)) } ?? .null,
            "stagesDone": .array(state.stagesReached.map { .init(Int($0)) }),
            "running": .bool(state.isRunning),
            "completed": .bool(state.isCompleted),
            "aliases": aliasFills(editorID, in: quests)
        ]
    }

    /// Each reference alias by name, with the reference that fills it or null.
    private func aliasFills(_ editorID: String, in quests: any QuestRuntimePort) -> AgentJSON {
        guard let quest = quests.quests.quest(editorID: editorID) else { return .null }
        let table = attempt { try quests.aliasState(of: quest.formID) }
        var fills: [String: AgentJSON] = [:]
        for alias in quest.aliases where alias.category == .reference {
            let name = alias.name ?? String(alias.id)
            fills[name] = table?.reference(forAlias: alias.id).map { .string("\($0)") } ?? .null
        }
        return .object(fills)
    }
}
