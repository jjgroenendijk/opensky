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
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuWorldTeleportsAdapter` reads from the session.
@MainActor
public protocol MenuWorldTeleportsHost: AnyObject, SendableMetatype {
    var agentWorld: any AgentWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var hud: any HUDPort { get }
    var loadingScreens: any LoadingScreenPort { get }
    var raceMenu: any RaceMenuPort { get }
    var renderer: (any RendererPort)? { get }
    var simulationClock: any SteppedWallClockPort { get }
    var streamer: any CellStreamerPort { get }
}

/// Part of `MenuWorldAdapter`, over its own narrow host.
public struct MenuWorldTeleportsAdapter {
    public let game: any MenuWorldTeleportsHost
    public let state: MenuPartState
}

extension MenuWorldTeleportsAdapter {
    /// Moves the player the way `debug.teleport` does.
    public func teleportPlayer(_ target: AgentTeleportTarget, openingRaceMenu: Bool) {
        movePlayer(openingRaceMenu: openingRaceMenu) { [game] () throws(AgentFailure) in
            try game.agentWorld.teleportJob(to: target)
        }
    }

    /// A launcher start option: the player moves there behind the loading screen,
    /// with no new game and no race menu.
    public func startPlayer(at start: LaunchStart) {
        let target: AgentTeleportTarget
        switch start {
        case .normal: return
        case let .cell(editorID): target = .cell(editorID)
        case let .exterior(worldspace, x, y): target = .grid(x: x, y: y, worldspace: worldspace)
        }
        state.coverNextTeleport = true
        teleportPlayer(target, openingRaceMenu: false)
    }

    /// A load puts the player back where the save was made, behind the loading screen.
    public func restorePlayerPlace(_ place: SavePlayerPlace) {
        state.coverNextTeleport = true
        movePlayer(openingRaceMenu: false) { [game] () throws(AgentFailure) in
            try game.agentWorld.teleportJob(to: place)
        }
    }

    /// The launcher's Follow Windows Game, behind the loading screen like a load.
    public func followView(_ target: AgentViewTarget) {
        state.coverNextTeleport = true
        movePlayer(openingRaceMenu: false) { [game] () throws(AgentFailure) in
            try game.agentWorld.viewJob(target)
        }
    }

    public func movePlayer(
        openingRaceMenu: Bool,
        job: () throws(AgentFailure) -> any AgentTeleportJobPort
    ) {
        state.raceMenuAfterTeleport = openingRaceMenu
        // In the same frame, so no world shows between the two covers.
        liftNewGameCover()
        if state.coverNextTeleport {
            state.coverNextTeleport = false
            state.teleportCovered = true
            game.loadingScreens.beginLoad(at: state.now().timeIntervalSinceReferenceDate)
        }
        do {
            state.newGameTeleport = try job().wait
        } catch {
            game.hud.showNotification("Move: \(error.message)")
            liftTeleportCover(at: state.now().timeIntervalSinceReferenceDate)
            openRaceMenuIfAsked()
            return
        }
        installStartTicker()
    }

    private func installStartTicker() {
        guard !state.startTickerInstalled, let gameSession = game.gameSession else { return }
        state.startTickerInstalled = true
        gameSession.frameSteps.register(.newGameTeleport) { [weak game, state] _ in
            guard let game else { return }
            MenuWorldTeleportsAdapter(game: game, state: state)
                .pollNewGameTeleport(now: state.now().timeIntervalSinceReferenceDate)
        }
    }

    public func coverUntilFirstMove() {
        state.newGameCoverSince = game.simulationClock.now
        attempt { try game.renderer?.setLoadingCover([]) }
        game.hud.setCovered(true)
        installStartTicker()
    }

    private func liftNewGameCover() {
        guard state.newGameCoverSince != nil else { return }
        state.newGameCoverSince = nil
        attempt { try game.renderer?.setLoadingCover(nil) }
        game.hud.setCovered(false)
    }

    /// The opening quest did not move the player, so the world loads where it stands.
    public func abandonNewGameCover() {
        liftNewGameCover()
        game.streamer.isHeld = false
    }

    private func pollNewGameTeleport(now: Double) {
        if
            let since = state.newGameCoverSince,
            game.simulationClock.now - since > Self.newGameCoverLimitSeconds
        {
            MenusLog.logger.warning("[WARNING] the opening quest did not move the player")
            abandonNewGameCover()
        }
        guard let wait = state.newGameTeleport, let result = wait.poll(now).finish else { return }
        state.newGameTeleport = nil
        if case let .failure(error) = result {
            game.hud.showNotification("Move: \(error.message)")
        }
        liftTeleportCover(at: now)
        openRaceMenuIfAsked()
    }

    /// A new or loaded game is played, so the player walks rather than flies.
    private func liftTeleportCover(at now: Double) {
        guard state.teleportCovered else { return }
        state.teleportCovered = false
        game.loadingScreens.loadFinished(at: now)
        game.gameSession?.setMovementMode(.walk)
    }

    private func openRaceMenuIfAsked() {
        guard state.raceMenuAfterTeleport else { return }
        state.raceMenuAfterTeleport = false
        game.raceMenu.open(limited: false)
    }
}

extension MenuWorldTeleportsAdapter {
    static let newGameCoverLimitSeconds = 30.0
}
