// `ScriptNodeBindingsAdapter` joins the started session: what `wirePaths` registered.

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
import OpenSkyPerception
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

/// Connects `ScriptNodeBindingsAdapter` to the started session.
public struct ScriptPathsWiring {
    public init(_ adapter: ScriptNodeBindingsAdapter, _ hooks: inout PapyrusGameNatives) {
        hooks.pathToReference = { [weak owner = adapter.owner] actor, target, speed, token in
            guard
                let owner, let streamer = adapter.game.streamer,
                let point = adapter.game.scripts.bridge?.referenceState(for: target)?.transform
                    .position
            else { return false }
            let started = streamer.moveActor(
                actor, to: point, direct: false, gait: ScriptPathWaits.gait(forSpeed: speed),
                runSlowdown: nil, walkRunBlend: speed
            )
            guard started == .started else { return false }
            owner.pathWaits.wait(token, for: actor)
            return true
        }
    }
}
