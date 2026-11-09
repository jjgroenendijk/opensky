// The Papyrus natives `ScriptNodeBindingsAdapter` fills as the bridge is built.

import Foundation
import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyObjectAnimation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyScripting
public import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension ScriptNodeBindingsAdapter {
    /// Fills these natives as the bridge is built.
    public func fillPaths(_ hooks: inout PapyrusGameNatives) {
        hooks.pathToReference = { actor, target, speed, token in
            let streamer = self.game.streamer
            guard
                let point = self.game.scripts.bridge?.referenceState(for: target)?.transform
                    .position
            else { return false }
            let started = streamer.moveActor(
                actor, to: point, direct: false, gait: ScriptPathWaits.gait(forSpeed: speed),
                runSlowdown: nil, walkRunBlend: speed
            )
            guard started == .started else { return false }
            self.state.pathWaits.wait(token, for: actor)
            return true
        }
    }
}
