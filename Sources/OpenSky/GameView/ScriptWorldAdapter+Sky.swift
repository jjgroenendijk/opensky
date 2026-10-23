// The sun and the sky a Papyrus script reads: `Game.GetSunPositionX`, the sun gaze of
// `OnPlayerBowShot`, and `Weather.GetSkyMode`. Values come from the renderer and the
// weather clock, so a script sees the sun the frame draws.

import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldState

extension ScriptWorldAdapter {
    /// `GetSkyMode` values (<https://ck.uesp.net/wiki/GetSkyMode_-_Weather>).
    private enum SkyMode {
        static let interior: Int32 = 1
        static let full: Int32 = 3
    }

    func wireSky(bridge: PapyrusWorldStateBridge) {
        bridge.sessionNatives.towardSun = { [weak game] in
            guard
                let game, game.streamer?.isInterior != true,
                let session = game.gameSession, let renderer = game.renderer,
                let weather = session.weather,
                weather.timeOfDayWeights(hour: session.gameClock.hourOfDay).night < 1
            else { return nil }
            return -renderer.camera.sunDirection
        }
        bridge.sessionNatives.playerView = { [weak game] in
            guard let camera = game?.gameSession?.freeFlyCamera else { return nil }
            return PapyrusPlayerView(eye: camera.position, forward: camera.forward)
        }
        bridge.sessionNatives.skyMode = { [weak game] in
            game?.streamer?.isInterior == true ? SkyMode.interior : SkyMode.full
        }
    }
}
