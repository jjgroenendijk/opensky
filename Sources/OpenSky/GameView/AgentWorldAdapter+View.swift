// The player's view as the reference game's console takes it, for `state view` and the
// Reference Game page (docs/tools/reference-game.md).

import Foundation
import OpenSkyAgentControl
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyPlayer
import OpenSkyReference
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyWeather
import OpenSkyWorld

extension AgentWorldAdapter {
    func referenceView() throws(AgentFailure) -> ReferenceView {
        guard let gameSession = game.gameSession, let streamer = game.streamer else {
            throw notReady()
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

    func viewState() throws(AgentFailure) -> AgentJSON {
        let view = try referenceView()
        guard
            let data = try? JSONEncoder().encode(view),
            let json = try? JSONDecoder().decode(AgentJSON.self, from: data)
        else { throw AgentFailure(.failed, "cannot encode the view") }
        return json
    }
}
