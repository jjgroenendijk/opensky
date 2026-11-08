import Foundation
public import OpenSkyAgentControl
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
public import OpenSkyReference
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySave
import OpenSkySaveInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface

/// What `AgentViewAdapter` reads from the session.
@MainActor
public protocol AgentViewHost: AnyObject {
    var benchmarkWorld: any BenchmarkWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentViewAdapter {
    public unowned let owner: AgentWorldAdapter
    public let game: any AgentViewHost
}

extension AgentViewAdapter {
    /// Sets the hour and weather now; the returned job moves the player and turns the camera.
    public func viewJob(_ target: AgentViewTarget) throws(AgentFailure) -> AgentTeleportJob {
        let cell = target.interiorCell.map { CellSceneLocation.interior(FormID(stored: $0)) }
            ?? .exterior(CellCoordinate(containing: target.feet))
        let place = SavePlayerPlace(
            cell: cell, feet: target.feet, yaw: target.yawDegrees * .pi / 180,
            worldspace: target.interiorCell == nil ? target.worldspace : nil
        )
        let job = try AgentTeleportJob(
            adapter: owner, place: place, pitch: target.pitchDegrees * .pi / 180
        )
        if let hour = target.hour {
            game.runtimeState.setGameClockHour(hour)
        }
        if let weather = target.weather {
            game.gameSession?.weather?.forceWeather(FormID(stored: weather), transition: .instant)
        }
        return job
    }

    public func referenceView() throws(AgentFailure) -> ReferenceView {
        guard let gameSession = game.gameSession, let streamer = game.streamer else {
            throw owner.notReady()
        }
        let camera = gameSession.freeFlyCamera
        let feet = gameSession.walkController.feetPosition
        let place: ReferencePlace
        if let interior = streamer.interiorScene {
            let name = interior.summary.cellName
            guard !name.hasPrefix("cell ") else {
                throw AgentFailure(.invalidArgument, "this interior has no editor ID for coc")
            }
            place = .interior(editorID: name)
        } else {
            let grid = CellCoordinate(containing: feet)
            place = .exterior(worldspace: streamer.worldspaceEditorID, grid: SIMD2(grid.x, grid.y))
        }
        return ReferenceView(
            feet: feet, yawDegrees: remainder(camera.yaw * 180 / .pi, 360),
            pitchDegrees: camera.pitch * 180 / .pi,
            fovYDegrees: gameSession.viewFOVYRadians * 180 / .pi,
            gameHour: game.runtimeState.runtimeStateClock.hourOfDay, place: place,
            weatherFormID: gameSession.weather?.currentWeatherID?.rawValue,
            firstPerson: gameSession.movementMode == .walk
        )
    }

    public func viewState() throws(AgentFailure) -> AgentJSON {
        let view = try referenceView()
        guard
            let data = try? JSONEncoder().encode(view),
            let json = try? JSONDecoder().decode(AgentJSON.self, from: data)
        else { throw AgentFailure(.failed, "cannot encode the view") }
        return json
    }

    public func benchmark(_ agentRequest: AgentBenchmarkRequest) throws(AgentFailure)
        -> AgentHandling
    {
        let tour = game.benchmarkWorld
        if agentRequest.stop {
            tour.stop()
            return .done(.success(["stopped": .bool(true)]))
        }
        guard !tour.isRunning else {
            throw AgentFailure(.notReady, "a benchmark tour is already running")
        }
        let before = tour.runCount
        try tour.start(agentRequest)
        return .waiting(AgentWait { [weak tour] _ in
            guard let tour else {
                return .done(.failure(AgentFailure(.notReady, "the game window closed")))
            }
            guard tour.runCount > before, let run = tour.lastRunJSON else { return .wait }
            return .done(.success(run))
        })
    }
}
