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
public import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension ScriptNodeBindingsAdapter {
    /// Fills these natives as the bridge is built.
    public func fillLineOfSight(bridge: PapyrusWorldStateBridge) {
        bridge.natives.perception.seesTarget = { viewer, target in
            self.sees(viewer: viewer, target: target, bridge: bridge)
        }
    }
}
