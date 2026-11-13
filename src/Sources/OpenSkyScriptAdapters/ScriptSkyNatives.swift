// The Papyrus natives `ScriptSkyBindingsAdapter` fills as the bridge is built.

import Foundation
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension ScriptSkyBindingsAdapter {
    /// Fills these natives as the bridge is built.
    public func fillSky(bridge: PapyrusWorldStateBridge) {
        bridge.natives.session.towardSun = { [weak game = self.game] in
            guard
                let game, game.streamer.isInterior != true,
                let session = game.gameSession, let renderer = game.renderer,
                let weather = session.weather,
                weather.timeOfDayWeights(hour: session.gameClock.hourOfDay).night < 1
            else { return nil }
            return renderer.frameInput.celestial?.sunDirection ?? -renderer.camera.sunDirection
        }
        bridge.natives.session.playerView = { [weak game = self.game] in
            guard let camera = game?.gameSession?.freeFlyCamera else { return nil }
            return PapyrusPlayerView(eye: camera.position, forward: camera.forward)
        }
        bridge.natives.session.skyMode = { [weak game = self.game] in
            game?.streamer.isInterior == true ? ScriptSkyBindingsAdapter.SkyMode
                .interior : ScriptSkyBindingsAdapter.SkyMode.full
        }
    }
}
