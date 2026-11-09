// `ObjectAnimationWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyObjectAnimation
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension ObjectAnimationWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(game: any ObjectAnimationWorldHost, stage: SessionStage?) {
        self.init(game: game)
        guard let stage else { return }
        registerObjectAnimation(stage: stage)
    }

    private func registerObjectAnimation(stage: SessionStage) {
        let gameSession = stage.gameSession
        guard game.audioFileSystem != nil else { return }
        gameSession.worldTick.register(.objectAnimation) { [weak self] delta in
            self?.advance(delta)
        }
    }
}
