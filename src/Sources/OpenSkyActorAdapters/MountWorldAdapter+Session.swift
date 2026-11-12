// `MountWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension MountWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some MountWorldHost & MountDragonRidingHost,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerMounts(stage: stage)
    }

    private func registerMounts(stage: SessionStage) {
        let gameSession = stage.gameSession
        gameSession.playerMount = self
        doorGate.registerDoorGate()
    }
}

/// A mounted player opens no door: the gate refuses it and says why.
final class MountDoorGate {
    let game: any MountWorldHost
    var mounts: any MountPort {
        game.mounts
    }

    init(game: any MountWorldHost) {
        self.game = game
    }

    func registerDoorGate() {
        let streamer = game.streamer
        streamer.activationGate.register(.mount) { [weak self] target in
            self?.mounts.isActive == true && target.interaction.action == .open ? .mounted : nil
        }
        streamer.activationGate.refusals.register(.mount) { [weak self] event in
            guard let self, event.refusal == .mounted else { return }
            _ = game.messages.postNotification(mounts.settings.doorRefusal)
        }
    }
}
