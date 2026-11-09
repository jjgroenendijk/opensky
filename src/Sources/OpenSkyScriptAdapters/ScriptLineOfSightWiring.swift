// `ScriptNodeBindingsAdapter` joins the started session: what `wireLineOfSight` registered.

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

/// Connects `ScriptNodeBindingsAdapter` to the started session.
public struct ScriptLineOfSightWiring {
    public init(_ adapter: ScriptNodeBindingsAdapter, bridge: PapyrusWorldStateBridge) {
        bridge.perceptionNatives.seesTarget = { viewer, target in
            adapter.sees(viewer: viewer, target: target, bridge: bridge)
        }
    }
}
