// `BeastFormWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension BeastFormWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(game: any BeastFormWorldHost, stage: SessionStage?) {
        self.init(game: game)
        guard let stage else { return }
        registerBeastForm(stage: stage)
    }

    private func registerBeastForm(stage: SessionStage) {
        let streamer = stage.streamer
        streamer.activationGate.register(.beastForm) { [weak self] target in
            guard let self else { return nil }
            let canTake = playerRace?.flags.contains(.canPickUpItems) ?? true
            return form.refusal(for: target.interaction.action, raceCanPickUpItems: canTake)
        }
    }
}
