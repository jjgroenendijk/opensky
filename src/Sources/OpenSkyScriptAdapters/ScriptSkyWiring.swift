// `ScriptSkyBindingsAdapter` joins the started session: what `wireSky` registered.

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

/// Connects `ScriptSkyBindingsAdapter` to the started session.
public struct ScriptSkyWiring {
    public init(_ adapter: ScriptSkyBindingsAdapter, bridge: PapyrusWorldStateBridge) {
        bridge.sessionNatives.towardSun = { [weak game = adapter.game] in
            guard
                let game, game.streamer.isInterior != true,
                let session = game.gameSession, let renderer = game.renderer,
                let weather = session.weather,
                weather.timeOfDayWeights(hour: session.gameClock.hourOfDay).night < 1
            else { return nil }
            return renderer.frameInput.celestial?.sunDirection ?? -renderer.camera.sunDirection
        }
        bridge.sessionNatives.playerView = { [weak game = adapter.game] in
            guard let camera = game?.gameSession?.freeFlyCamera else { return nil }
            return PapyrusPlayerView(eye: camera.position, forward: camera.forward)
        }
        bridge.sessionNatives.skyMode = { [weak game = adapter.game] in
            game?.streamer.isInterior == true ? ScriptSkyBindingsAdapter.SkyMode
                .interior : ScriptSkyBindingsAdapter.SkyMode.full
        }
    }
}
