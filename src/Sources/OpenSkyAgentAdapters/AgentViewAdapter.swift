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
import OpenSkySaveInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface

/// What `AgentViewAdapter` reads from the session.
@MainActor
public protocol AgentViewHost: AnyObject, SendableMetatype {
    var benchmarkWorld: any BenchmarkWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var streamer: any CellStreamerPort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentViewAdapter {
    public let hub: AgentHub
    public let game: any AgentViewHost
}

extension AgentViewAdapter {
    /// Sets the hour and weather now; the returned job moves the player and turns the camera.
    public func viewJob(_ target: AgentViewTarget) throws(AgentFailure) -> AgentTeleportJob {
        let cell = target.interiorCell.map { CellSceneLocation.interior(FormID(stored: $0)) }
            ?? .exterior(CellCoordinate(containing: target.feet))
        let place = SavePlayerPlace(
            cell: cell, feet: target.feet, yaw: MatrixMath.radians(fromDegrees: target.yawDegrees),
            worldspace: target.interiorCell == nil ? target.worldspace : nil
        )
        let weather = target.weather.map { FormID(stored: $0) }
        if
            let weather, let system = game.gameSession?.weather,
            system.store.weather(weather) == nil
        {
            throw AgentFailure(
                .invalidArgument, "no weather has the FormID \(weather)"
            )
        }
        let job = try AgentTeleportJob(
            hub: hub, place: place,
            pitch: MatrixMath.radians(fromDegrees: target.pitchDegrees)
        )
        if let hour = target.hour {
            game.runtimeState.setGameClockHour(hour)
        }
        if let weather {
            game.gameSession?.weather?.forceWeather(weather, transition: .instant)
        }
        return job
    }

    public func referenceView() throws(AgentFailure) -> ReferenceView {
        let streamer = game.streamer
        guard let gameSession = game.gameSession else {
            throw hub.notReady()
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
            feet: feet, yawDegrees: MatrixMath.signedDegrees(fromRadians: camera.yaw),
            pitchDegrees: MatrixMath.degrees(fromRadians: camera.pitch),
            fovYDegrees: MatrixMath.degrees(fromRadians: gameSession.viewFOVYRadians),
            gameHour: game.runtimeState.runtimeStateClock.hourOfDay, place: place,
            weatherFormID: gameSession.weather?.currentWeatherID?.rawValue,
            firstPerson: gameSession.movementMode == .walk
        )
    }

    public func viewState() throws(AgentFailure) -> AgentJSON {
        let view = try referenceView()
        guard
            let data = attempt({ try JSONEncoder().encode(view) }),
            let json = attempt({ try JSONDecoder().decode(AgentJSON.self, from: data) })
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
