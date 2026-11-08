import Foundation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
public import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkySave
public import OpenSkySaveInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuWorldTeleportsAdapter` reads from the session.
@MainActor
public protocol MenuWorldTeleportsHost: AnyObject {
    var agentWorld: any AgentWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var hud: any HUDPort { get }
    var loadingScreens: any LoadingScreenPort { get }
    var raceMenu: any RaceMenuPort { get }
    var renderer: (any RendererPort)? { get }
    var simulationClock: any SteppedWallClockPort { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `MenuWorldAdapter`, over its own narrow host.
public struct MenuWorldTeleportsAdapter {
    public unowned let owner: MenuWorldAdapter
    public unowned let game: any MenuWorldTeleportsHost
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
        owner.coverNextTeleport = true
        teleportPlayer(target, openingRaceMenu: false)
    }

    /// A load puts the player back where the save was made, behind the loading screen.
    public func restorePlayerPlace(_ place: SavePlayerPlace) {
        owner.coverNextTeleport = true
        movePlayer(openingRaceMenu: false) { [game] () throws(AgentFailure) in
            try game.agentWorld.teleportJob(to: place)
        }
    }

    /// The launcher's Follow Windows Game, behind the loading screen like a load.
    public func followView(_ target: AgentViewTarget) {
        owner.coverNextTeleport = true
        movePlayer(openingRaceMenu: false) { [game] () throws(AgentFailure) in
            try game.agentWorld.viewJob(target)
        }
    }

    public func movePlayer(
        openingRaceMenu: Bool,
        job: () throws(AgentFailure) -> any AgentTeleportJobPort
    ) {
        owner.raceMenuAfterTeleport = openingRaceMenu
        // In the same frame, so no world shows between the two covers.
        liftNewGameCover()
        if owner.coverNextTeleport {
            owner.coverNextTeleport = false
            owner.teleportCovered = true
            game.loadingScreens.beginLoad(at: Date().timeIntervalSinceReferenceDate)
        }
        do {
            owner.newGameTeleport = try job().wait
        } catch {
            game.hud.showNotification("Move: \(error.message)")
            liftTeleportCover(at: Date().timeIntervalSinceReferenceDate)
            openRaceMenuIfAsked()
            return
        }
        installStartTicker()
    }

    private func installStartTicker() {
        guard !owner.startTickerInstalled, let gameSession = game.gameSession else { return }
        owner.startTickerInstalled = true
        gameSession.frameSteps.register(.newGameTeleport) { [weak owner] _ in
            owner?.teleports.pollNewGameTeleport(now: Date().timeIntervalSinceReferenceDate)
        }
    }

    public func coverUntilFirstMove() {
        owner.newGameCoverSince = game.simulationClock.now
        try? game.renderer?.setLoadingCover([])
        game.hud.setCovered(true)
        installStartTicker()
    }

    private func liftNewGameCover() {
        guard owner.newGameCoverSince != nil else { return }
        owner.newGameCoverSince = nil
        try? game.renderer?.setLoadingCover(nil)
        game.hud.setCovered(false)
    }

    /// The opening quest did not move the player, so the world loads where it stands.
    public func abandonNewGameCover() {
        liftNewGameCover()
        game.streamer?.isHeld = false
    }

    private func pollNewGameTeleport(now: Double) {
        if
            let since = owner.newGameCoverSince,
            game.simulationClock.now - since > MenuWorldAdapter.newGameCoverLimitSeconds
        {
            MenuWorldAdapter.logger.warning("[WARNING] the opening quest did not move the player")
            abandonNewGameCover()
        }
        guard let wait = owner.newGameTeleport, let result = wait.poll(now).finish else { return }
        owner.newGameTeleport = nil
        if case let .failure(error) = result {
            game.hud.showNotification("Move: \(error.message)")
        }
        liftTeleportCover(at: now)
        openRaceMenuIfAsked()
    }

    /// A new or loaded game is played, so the player walks rather than flies.
    private func liftTeleportCover(at now: Double) {
        guard owner.teleportCovered else { return }
        owner.teleportCovered = false
        game.loadingScreens.loadFinished(at: now)
        game.gameSession?.setMovementMode(.walk)
    }

    private func openRaceMenuIfAsked() {
        guard owner.raceMenuAfterTeleport else { return }
        owner.raceMenuAfterTeleport = false
        game.raceMenu.open(limited: false)
    }
}
