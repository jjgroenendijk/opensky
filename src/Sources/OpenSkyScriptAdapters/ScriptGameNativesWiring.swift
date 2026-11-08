// `ScriptSessionBindingsAdapter` joins the started session: what `wireGameNatives` registered.

import Foundation
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAgentControl
import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMenus
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
        bridge: PapyrusWorldStateBridge,
        provider: WorldDataStores
    ) {
        var hooks = PapyrusGameNatives()
        _ = ScriptSaveAndScreenWiring(adapter, &hooks)
        _ = ScriptPlayerRulesWiring(adapter.owner.playerBindings, &hooks)
        _ = ScriptReferenceRulesWiring(adapter.owner.referenceBindings, &hooks, provider: provider)
        _ = ScriptSoundsWiring(adapter.owner.soundBindings, &hooks)
        _ = ScriptPathsWiring(adapter.owner.nodeBindings, &hooks)
        hooks.playBink = { [weak movies = adapter.game.movieWorld] request, token in
            movies?.playBink(request, waitToken: token) ?? false
        }
        hooks.nodeTransform = adapter.owner.modelNodes.flatMap { nodes in
            { [weak owner = adapter.owner] key, name, then in
                owner?.nodeBindings
                    .nodeTransform(of: key, named: name, nodes: nodes, then: then) ?? .missing
            }
        }
        bridge.gameNatives = hooks
    }
}
