// The player's cart seat and exit idles resolve to clips, and each clip decodes
// against the rig the idle coordinator gives the player. Names and counts only.

import Foundation
@testable import OpenSkyActorPresentation
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyWorldInterface
import Testing

@MainActor
struct PlayerCartIdleRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func thePlayersCartIdlesLoadAgainstThePlayerRig() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let files = VirtualFileSystem(root: root)
        let store = IdleStore(plugins: ActivePluginFiles.load(root: root))
        let resolver = IdlePlaybackResolver(files: files, animatedObjects: store.animatedObjects)
        let load = ActorClipLoader.load(files: files)
        for editorID in ["IdleCartPrisonerCIdle", "IdleCartPrisonerCExit"] {
            let picked = try #require(
                store.idles.records.first { $0.record.editorID == editorID }, "\(editorID)"
            )
            let idle = store.inheritingBehaviorFile(picked)
            let plan = resolver.plan(for: idle)
            #expect(!plan.clipPaths.isEmpty, "\(editorID) resolved to no clip")
            for path in plan.clipPaths {
                let key = ActorClipKey(
                    skeletonMeshPath: IdleCoordinator.playerSkeletonPath, animationPath: path
                )
                #expect(throws: Never.self, "\(editorID): \(path)") { _ = try load(key) }
            }
        }
    }
}
