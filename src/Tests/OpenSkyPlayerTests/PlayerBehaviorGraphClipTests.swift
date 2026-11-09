// The player graph finds a clip by a name relative to its project folder, such as a paired
// kill move in the shared kill move folder, whether it reads clips inline or on a worker.

import Foundation
@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import OpenSkyGameData
@testable import OpenSkyPlayer
import Testing

struct PlayerBehaviorGraphClipTests {
    private static let name = "..\\SharedKillMoves\\Human&SabreCat\\Paired_1HMKillMove.hkx"
    private static let path =
        "meshes\\actors\\sharedkillmoves\\human&sabrecat\\paired_1hmkillmove.hkx"

    private static func files() throws -> PlayerBehaviorGraphFiles {
        try PlayerBehaviorGraphFiles(
            behaviorPath: BehaviorProjectFixture.folder + "\\behaviors\\0_master.hkx",
            objectGraph: BehaviorProjectFixture.objectGraph(),
            behavior: BehaviorProjectFixture.behavior,
            rig: BehaviorProjectFixture.rig,
            ragdoll: nil,
            clipPaths: [],
            projectFolder: BehaviorProjectFixture.folder
        )
    }

    @Test func aWorkerLoadsARelativeClip() throws {
        let clip = try BehaviorFixture.splineClip()
        let graph = try PlayerBehaviorGraph.build(
            Self.files(),
            fileSystem: InMemoryFileSource(),
            clipWorker: ImmediateAssetLoadWorker<String, SplineBehaviorClip> { path in
                #expect(path == Self.path)
                return clip
            }
        )
        graph.clips.prefetch(named: Self.name)
        #expect(graph.clips.drain() == 1)
        #expect(graph.clips.clip(named: Self.name, bindingIndex: -1) != nil)
    }

    @Test func anInlineReadMissesAnAbsentRelativeClip() throws {
        let graph = try PlayerBehaviorGraph.build(Self.files(), fileSystem: InMemoryFileSource())
        #expect(graph.clips.clip(named: Self.name, bindingIndex: -1) == nil)
        #expect(graph.clips.missCount == 1)
    }
}
