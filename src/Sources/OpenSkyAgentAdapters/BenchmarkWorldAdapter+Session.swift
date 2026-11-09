// `BenchmarkWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

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
import OpenSkySessionInterface
import OpenSkyWeather
public import OpenSkyWorld
import OpenSkyWorldInterface
import QuartzCore
import simd

extension BenchmarkWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some BenchmarkWorldHost & BenchmarkTourSettingsHost,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerBenchmark(stage: stage)
    }

    private func registerBenchmark(stage: SessionStage) {
        let gameSession = stage.gameSession
        gameSession.frameSteps.register(.benchmark) { [weak self] _ in
            self?.frame()
        }
    }
}
