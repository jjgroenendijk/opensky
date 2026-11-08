// `Actor.PathToReference`: the walk goes through the streamer's movement authority,
// and the call waits until the actor stops.

import Foundation
import OpenSkyAIPackages
import OpenSkyFormatsESM
import OpenSkyNavigation
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension ScriptWorldAdapter {
    func wirePaths(_ hooks: inout PapyrusGameNatives) {
        hooks.pathToReference = { [weak self] actor, target, speed, token in
            guard
                let self, let streamer = game.streamer,
                let point = game.scripts.bridge?.referenceState(for: target)?.transform.position
            else { return false }
            let started = streamer.moveActor(
                actor, to: point, direct: false, gait: ScriptPathWaits.gait(forSpeed: speed),
                runSlowdown: nil, walkRunBlend: speed
            )
            guard started == .started else { return false }
            pathWaits.wait(token, for: actor)
            return true
        }
    }

    func answerPathWaits() {
        if !pathWaits.isEmpty, let streamer = game.streamer {
            pathWaitAnswers.merge(pathWaits.settle(streamer.npcMovementReadouts())) { first, _ in
                first
            }
        }
        guard let scheduler = game.scripts.runtime?.scheduler else { return }
        pathWaitAnswers = pathWaitAnswers.filter { token, arrived in
            !scheduler.answer(token, returning: .boolean(arrived))
        }
    }
}
