// `debug.view` and the launcher's Follow Windows Game: the player takes a whole view at
// once, such as the Windows reference game's (docs/tools/reference-game.md).

import Foundation
import OpenSkyAgentControl
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRuntimeState
import OpenSkySave
import OpenSkyWeather
import OpenSkyWorld

extension AgentWorldAdapter {
    /// Sets the hour and weather now; the returned job moves the player and turns the camera.
    func viewJob(_ target: AgentViewTarget) throws(AgentFailure) -> AgentTeleportJob {
        let cell = target.interiorCell.map { CellSceneLocation.interior(FormID(stored: $0)) }
            ?? .exterior(CellCoordinate(containing: target.feet))
        let place = SavePlayerPlace(
            cell: cell, feet: target.feet, yaw: target.yawDegrees * .pi / 180,
            worldspace: target.interiorCell == nil ? target.worldspace : nil
        )
        let job = try AgentTeleportJob(
            adapter: self, place: place, pitch: target.pitchDegrees * .pi / 180
        )
        if let hour = target.hour {
            game.runtimeState.setGameClockHour(hour)
        }
        if let weather = target.weather {
            game.gameSession?.weather?.forceWeather(FormID(stored: weather), transition: .instant)
        }
        return job
    }
}
