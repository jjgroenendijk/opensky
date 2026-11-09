// `ScriptSessionBindingsAdapter` joins the started session: what `wireGameNatives` registered.

import Foundation
import OpenSkyActorPresentation
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
public import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Connects `ScriptSessionBindingsAdapter` to the started session.
public struct ScriptGameNativesWiring {
    public init(
        _ adapter: ScriptSessionBindingsAdapter,
        bridge: PapyrusWorldStateBridge
    ) {
        var hooks = PapyrusGameNatives()
        _ = ScriptSaveAndScreenWiring(adapter, &hooks)
        _ = ScriptPlayerRulesWiring(adapter.playerBindings, &hooks)
        _ = ScriptReferenceRulesWiring(adapter.referenceBindings, &hooks)
        _ = ScriptSoundsWiring(adapter.soundBindings, &hooks)
        _ = ScriptPathsWiring(adapter.nodeBindings, &hooks)
        hooks.playBink = { [weak movies = adapter.game.movieWorld] request, token in
            movies?.playBink(request, waitToken: token) ?? false
        }
        hooks.nodeTransform = adapter.state.modelNodes.flatMap { nodes in
            { [nodeBindings = adapter.nodeBindings] key, name, then in
                nodeBindings.nodeTransform(of: key, named: name, nodes: nodes, then: then)
            }
        }
        bridge.gameNatives = hooks
    }
}
