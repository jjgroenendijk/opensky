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
        ScriptModelNodeLoader(game: game, state: state).fillModelNodes(
            files: provider.scriptFileSystem
        ) { drain in
            gameSession.assetDrains.register(.modelNodes) { _ in drain() }
        }
    }
}

extension ScriptModelNodeLoader {
    /// `register` schedules the drain that takes in each loaded model.
    func fillModelNodes(
        files: (any GameFileSource)?, register: (@escaping () -> Void) -> Void
    ) {
        guard let files else { return }
        let nodes = AssetLoader<String, [String: PosedBone]> { path in
            try ScriptModelNodeLoader
                .nodeTransforms(in: NIFFile(data: files.contents(forPath: path)))
        }
        state.modelNodes = nodes
        register {
            nodes.drain()
            self.answerNodeWaits()
        }
    }
}
