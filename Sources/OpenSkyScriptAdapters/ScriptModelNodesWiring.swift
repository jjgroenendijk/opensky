// `ScriptNodeBindingsAdapter` joins the started session: what `wireModelNodes` registered.

import Foundation
import OpenSkyActorPresentation
import OpenSkyAIPackages
public import OpenSkyCells
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
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Connects `ScriptNodeBindingsAdapter` to the started session.
public struct ScriptModelNodesWiring {
    public init(
        _ adapter: ScriptNodeBindingsAdapter,
        provider: WorldDataStores,
        gameSession: GameSession
    ) {
        guard let files = provider.scriptFileSystem else { return }
        let nodes = AssetLoader<String, [String: PosedBone]> { path in
            try ScriptNodeBindingsAdapter
                .nodeTransforms(in: NIFFile(data: files.contents(forPath: path)))
        }
        adapter.owner.modelNodes = nodes
        gameSession.assetDrains.register(.modelNodes) { [weak owner = adapter.owner] _ in
            nodes.drain()
            owner?.nodeBindings.answerNodeWaits()
        }
    }
}
