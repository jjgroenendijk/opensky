// The Papyrus natives `ScriptSessionBindingsAdapter` fills as the bridge is built.

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

extension ScriptSessionBindingsAdapter {
    /// Fills these natives as the bridge is built.
    public func fillGameNatives(bridge: PapyrusWorldStateBridge) {
        var hooks = PapyrusGameNatives()
        fillSaveAndScreen(&hooks)
        playerBindings.fillPlayerRules(&hooks)
        referenceBindings.fillReferenceRules(&hooks)
        soundBindings.fillSounds(&hooks)
        nodeBindings.fillPaths(&hooks)
        hooks.playBink = { [weak movies = self.game.movieWorld] request, token in
            movies?.playBink(request, waitToken: token) ?? false
        }
        hooks.nodeTransform = state.modelNodes.flatMap { nodes in
            { [nodeBindings = self.nodeBindings] key, name, then in
                nodeBindings.nodeTransform(of: key, named: name, nodes: nodes, then: then)
            }
        }
        bridge.gameNatives = hooks
    }
}
