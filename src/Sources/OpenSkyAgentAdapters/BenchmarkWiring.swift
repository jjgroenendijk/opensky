// `BenchmarkWorldAdapter` joins the started session: what `wire` registered.

import Metal
import OpenSkyAgentControl
import OpenSkyCells
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkySession
import OpenSkySessionInterface
import OpenSkyWeather
public import OpenSkyWorld
import OpenSkyWorldInterface
import QuartzCore
import simd

/// Connects `BenchmarkWorldAdapter` to the started session.
public struct BenchmarkWiring {
    public init(_ adapter: BenchmarkWorldAdapter, gameSession: GameSession) {
        gameSession.frameSteps.register(.benchmark) { [weak adapter] _ in
            adapter?.frame()
        }
    }
}
