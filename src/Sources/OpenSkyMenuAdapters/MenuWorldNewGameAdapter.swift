import Foundation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagicInterface
import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuWorldNewGameAdapter` reads from the session.
@MainActor
public protocol MenuWorldNewGameHost: AnyObject, SendableMetatype {
    var agentWorld: any AgentWorldPort { get }
    var effectsWorld: any EffectsWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var inventory: any InventoryPort { get }
    var menuRecords: (any MenuRecordsPort)? { get }
    var messages: any MessageCoordinatorPort { get }
    var player: any PlayerPort { get }
    var saveGames: any SaveGameWorldPort { get }
    var scripts: any ScriptPort { get }
    var storyWorld: any StoryWorldPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `MenuWorldAdapter`, over its own narrow host.
public struct MenuWorldNewGameAdapter {
    public let game: any MenuWorldNewGameHost
    public let state: MenuPartState
    public let teleports: MenuWorldTeleportsAdapter
}

extension MenuWorldNewGameAdapter {
    /// The opening quest places the player and opens the race menu itself.
    /// A chosen cell is a test start, so the race menu opens there at once.
    public func startNewGame(at start: NewGameStart) {
        switch start {
        case .vanilla:
            resetSession()
            teleports.coverUntilFirstMove()
            if !game.storyWorld.startOpeningQuest() {
                teleports.abandonNewGameCover()
            }
        case let .cell(editorID):
            begin(LaunchNewGame(start: .cell(editorID)), at: .target(.cell(editorID)))
        }
    }

    /// A new game at a chosen place, with the hour, weather, story state, and items
    /// the launcher or `debug newgame` asked for. A start the load order lacks throws
    /// before anything changes.
    public func startNewGame(_ plan: LaunchNewGame) throws(AgentFailure) {
        try begin(plan, at: destination(of: plan.start))
    }

    public func startNewGame(_ request: AgentNewGameRequest) throws(AgentFailure) {
        let text = LaunchNewGameText(
            start: request.start, hour: request.hour.map { String($0) } ?? "",
            weather: request.weather ?? "", story: request.story, items: request.items,
            opensRaceMenu: request.opensRaceMenu
        )
        switch text.validate() {
        case let .success(plan): try startNewGame(plan)
        case let .failure(problem): throw AgentFailure(.invalidArgument, problem.reason)
        }
    }

    var lastNewGame: AgentNewGameRequest? {
        state.lastNewGame.map { plan in
            AgentNewGameRequest(
                start: plan.start.storedValue, hour: plan.hour, weather: plan.weather,
                story: plan.story.rawValue, items: plan.items.rawValue,
                opensRaceMenu: plan.opensRaceMenu
            )
        }
    }

    private enum Destination {
        case target(AgentTeleportTarget)
        /// A spot whose cell loads before the player stands there.
        case place(SavePlayerPlace)
    }

    private func destination(of start: LaunchStart) throws(AgentFailure) -> Destination {
        switch start {
        case .normal:
            throw AgentFailure(.invalidArgument, "a new game at a place needs a place")
        case let .cell(editorID):
            return .target(.cell(editorID))
        case let .exterior(worldspace, x, y):
            return .target(.grid(x: x, y: y, worldspace: worldspace))
        case let .marker(worldspace, plugin, objectID):
            let reference = ResolvedFormID(plugin: plugin, objectID: objectID)
            guard let marker = game.menuRecords?.menuRecords?.markers.marker(reference) else {
                throw AgentFailure(
                    .notFound, "no map marker \(start.storedValue) in the load order"
                )
            }
            let yaw = game.gameSession?.freeFlyCamera.yaw ?? 0
            return .place(SavePlayerPlace(
                cell: .exterior(CellCoordinate(containing: marker.position)), feet: marker.position,
                yaw: yaw, worldspace: worldspace
            ))
        }
    }

    private func begin(_ plan: LaunchNewGame, at destination: Destination) {
        resetSession()
        state.lastNewGame = plan
        switch plan.story {
        case .notStarted: break
        case .helgenHadvar: game.storyWorld.skipOpeningQuest(side: .hadvar)
        case .helgenRalof: game.storyWorld.skipOpeningQuest(side: .ralof)
        }
        if let hour = plan.clockHour {
            teleports.run(.setTime(hour: hour))
        }
        state.arrivalSteps = Self.arrivalSteps(of: plan)
        switch destination {
        case let .target(target):
            teleports.teleportPlayer(target, openingRaceMenu: plan.opensRaceMenu)
        case let .place(place):
            teleports
                .movePlayer(openingRaceMenu: plan.opensRaceMenu) { [game] () throws(AgentFailure) in
                    try game.agentWorld.teleportJob(to: place)
                }
        }
    }

    /// The weather and the items wait for the arrival, because both need a loaded world.
    public static func arrivalSteps(of plan: LaunchNewGame) -> [AgentDebugCommand] {
        let weather: [AgentDebugCommand] = plan.weather.map { [.weather($0)] } ?? []
        return weather + plan.items.items.map { item in
            .addItem(
                reference: "player", item: item.editorID, count: item.count, equip: item.equips
            )
        }
    }

    /// A fresh session: empty world state, the start clock, and the start-up quests.
    private func resetSession() {
        game.worldState.restore(from: .empty)
        game.inventory.alchemyLab.registerCreatedPotions()
        game.gameSession?.gameClock = GameClock()
        game.gameSession?.clearScriptScreenEffects()
        game.effectsWorld.fadeOutHealthCues()
        game.scripts.restore(instances: [], timers: [])
        game.messages.reloadHelpRecords()
        game.storyWorld.rerunSessionStart()
        game.saveGames.resetPlayTime()
        game.player.refreshBody()
        state.coverNextTeleport = true
    }

    public func holdWorldLoading() {
        game.streamer.isHeld = true
    }

    public func quitApplication() {
        state.terminateApp()
    }
}
