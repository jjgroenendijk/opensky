// The Papyrus natives `ScriptNodeBindingsAdapter` fills as the bridge is built.

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

extension ScriptNodeBindingsAdapter {
    /// Fills these natives as the bridge is built.
    public func fillModelNodes(provider: WorldDataStores, gameSession: GameSession) {
        ScriptModelNodeLoader(game: game, state: state)
            .fillModelNodes(provider: provider, gameSession: gameSession)
    }
}

extension ScriptModelNodeLoader {
    func fillModelNodes(provider: WorldDataStores, gameSession: GameSession) {
        guard let files = provider.scriptFileSystem else { return }
        let nodes = AssetLoader<String, [String: PosedBone]> { path in
            try ScriptModelNodeLoader
                .nodeTransforms(in: NIFFile(data: files.contents(forPath: path)))
        }
        state.modelNodes = nodes
        gameSession.assetDrains.register(.modelNodes) { _ in
            nodes.drain()
            self.answerNodeWaits()
        }
    }
}
