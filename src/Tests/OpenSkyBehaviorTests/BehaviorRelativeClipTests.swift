// A clip generator can name a clip outside its own animations folder through a relative
// path, such as a paired kill move in the shared kill move folder. The clip source
// resolves that name from the project folder.

import Foundation
@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import OpenSkyGameData
import Testing

struct BehaviorRelativeClipTests {
    private static let killMove =
        "meshes\\actors\\sharedkillmoves\\human&sabrecat\\paired_1hmkillmove_sabrecatshorta.hkx"

    @Test func joinResolvesDotComponents() {
        let folder = "meshes\\actors\\character"
        #expect(
            BehaviorProjectAsset.join(
                folder, "..\\SharedKillMoves\\Human&SabreCat\\Paired_1HMKillMove_SabreCatShortA.hkx"
            ) == Self.killMove
        )
        #expect(
            BehaviorProjectAsset.join(
                "meshes\\actors\\character\\_1stperson",
                "../Animations/./x.hkx"
            )
                == "meshes\\actors\\character\\animations\\x.hkx"
        )
        #expect(BehaviorProjectAsset
            .join(folder, "Animations\\Walk.hkx") == folder + "\\animations\\walk.hkx")
    }

    @Test func joinKeepsAParentAboveTheRoot() {
        #expect(BehaviorProjectAsset.join("meshes", "..\\..\\x.hkx") == "..\\x.hkx")
        #expect(BehaviorProjectAsset.join("", "..\\x.hkx") == "..\\x.hkx")
    }

    @Test func aRelativeClipOutsideTheIndexLoadsFromTheProjectFolder() throws {
        let clip = try BehaviorFixture.splineClip()
        let expected = Self.killMove
        let source = InstallBehaviorClipSource(
            paths: ["meshes\\actors\\character\\animations\\walk.hkx"],
            projectFolder: "meshes\\actors\\character",
            worker: ImmediateAssetLoadWorker<String, SplineBehaviorClip> { path in
                guard path == expected else { throw RelativeClipTestError.wrongPath(path) }
                return clip
            }
        )
        let name = "..\\SharedKillMoves\\Human&SabreCat\\Paired_1HMKillMove_SabreCatShortA.hkx"
        #expect(source.clip(named: name, bindingIndex: -1) == nil)
        #expect(source.isLoading(named: name, bindingIndex: -1))
        source.drain()
        #expect(source.clip(named: name, bindingIndex: -1)?.duration == clip.duration)
        #expect(source.missCount == 0)
    }

    @Test func aProjectSourceStartsAtTheProjectFolder() throws {
        let clip = try BehaviorFixture.splineClip()
        let expected = Self.killMove
        let asset = try BehaviorProjectFixture.asset()
        #expect(asset.projectFolder == BehaviorProjectFixture.folder)
        let source = InstallBehaviorClipSource(
            project: asset,
            worker: ImmediateAssetLoadWorker<String, SplineBehaviorClip> { path in
                guard path == expected else { throw RelativeClipTestError.wrongPath(path) }
                return clip
            }
        )
        let name = "..\\SharedKillMoves\\Human&SabreCat\\Paired_1HMKillMove_SabreCatShortA.hkx"
        source.prefetch(named: name)
        #expect(source.drain() == 1)
        #expect(source.clip(named: name, bindingIndex: -1)?.duration == clip.duration)
    }

    @Test func aBareNameOutsideTheIndexStaysAMiss() throws {
        let clip = try BehaviorFixture.splineClip()
        let source = InstallBehaviorClipSource(
            paths: [],
            projectFolder: "meshes\\actors\\character",
            worker: ImmediateAssetLoadWorker<String, SplineBehaviorClip> { _ in clip }
        )
        #expect(source.clip(named: "walk.hkx", bindingIndex: -1) == nil)
        #expect(!source.isLoading(named: "walk.hkx", bindingIndex: -1))
        #expect(source.missCount == 1)
    }

    @Test func withoutAProjectFolderARelativeNameIsAMiss() throws {
        let clip = try BehaviorFixture.splineClip()
        let source = InstallBehaviorClipSource(
            paths: [],
            worker: ImmediateAssetLoadWorker<String, SplineBehaviorClip> { _ in clip }
        )
        source.prefetch(named: "..\\SharedKillMoves\\x.hkx")
        #expect(source.drain() == 0)
        #expect(source.clip(named: "..\\SharedKillMoves\\x.hkx", bindingIndex: -1) == nil)
    }

    @Test func aFileSetSourceLooksUpARelativeNameFromItsFolder() throws {
        let set = try #require(BehaviorGapSweep.fileSets(in: [
            "meshes\\actors\\character\\behaviors\\0_master.hkx",
            "meshes\\actors\\character\\animations\\walk.hkx"
        ]).first)
        let source = InstallBehaviorClipSource(fileSystem: InMemoryFileSource(), files: set)
        // Neither file holds bytes, so each lookup misses, but the relative one is tried.
        #expect(source.clip(named: "..\\SharedKillMoves\\x.hkx", bindingIndex: -1) == nil)
        #expect(source.clip(named: "walk.hkx", bindingIndex: -1) == nil)
        #expect(source.clip(named: "run.hkx", bindingIndex: -1) == nil)
        #expect(source.missCount == 3)
    }

    @Test func aFileSetKnowsItsActorFolder() {
        let sets = BehaviorGapSweep.fileSets(in: [
            "meshes\\actors\\character\\_1stperson\\behaviors\\0_master.hkx",
            "meshes\\actors\\character\\behaviors\\0_master.hkx"
        ])
        #expect(
            sets.map(\.folder)
                == ["meshes\\actors\\character\\_1stperson", "meshes\\actors\\character"]
        )
    }
}

private enum RelativeClipTestError: Error {
    case wrongPath(String)
}
