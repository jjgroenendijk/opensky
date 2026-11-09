// `ActivationRefusalWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCombatInterface
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension ActivationRefusalWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(game: any ActivationRefusalWorldHost, stage: SessionStage?) {
        self.init(game: game)
        guard let stage else { return }
        registerActivationRefusal(stage: stage)
    }

    private func registerActivationRefusal(stage: SessionStage) {
        let streamer = stage.streamer
        streamer.activationGate.register(.notice) { [weak self] target in
            guard let self else { return nil }
            let texts = game.mapWorld.settingTexts(ActivationRefusalText.self)
            return ActivationRefusalRule.refusal(facts(for: target), texts: texts).map {
                .notice($0)
            }
        }
        streamer.activationGate.refusals.register(.notice) { [weak self] event in
            guard let self, case let .notice(text) = event.refusal else { return }
            game.hud.showNotification(text)
        }
    }
}
