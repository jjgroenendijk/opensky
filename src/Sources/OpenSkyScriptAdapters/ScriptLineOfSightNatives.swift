// The line-of-sight natives, filled as the bridge is built.

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
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Fills the line-of-sight natives from the node reads of `ScriptNodeBindingsAdapter`.
struct ScriptLineOfSightNatives {
    let nodes: ScriptNodeBindingsAdapter

    func fill(bridge: PapyrusWorldStateBridge) {
        bridge.natives.perception.seesTarget = { viewer, target in
            nodes.sees(viewer: viewer, target: target, bridge: bridge)
        }
    }
}
