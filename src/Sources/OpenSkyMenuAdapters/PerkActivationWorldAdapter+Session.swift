// `PerkActivationWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyProgressionInterface
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension PerkActivationWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(game: any PerkActivationWorldHost, stage: SessionStage?) {
        self.init(game: game)
        guard let stage else { return }
        registerPerkActivation(stage: stage)
    }

    private func registerPerkActivation(stage: SessionStage) {
        let streamer = stage.streamer
        streamer.activationGate.perkChoices = { [weak game = self.game] target in
            game?.perkActivation.activate(target) ?? false
        }
    }
}
