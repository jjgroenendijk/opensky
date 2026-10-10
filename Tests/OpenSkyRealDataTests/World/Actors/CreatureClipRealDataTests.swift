// Every creature skeleton a vanilla RACE names must find and decode an idle, a walk, and a
// run clip among its candidate names. The census goes to .logs/creature-clips/.

import Foundation
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyPhysics
@testable import OpenSkyWorld
import Testing

struct CreatureClipRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func everyCreatureSkeletonPlaysIdleWalkAndRun() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let files = VirtualFileSystem(root: root)
        let skeletons = try Self.creatureSkeletons(root: root, files: files)
        var lines: [String] = []
        var failures: [String] = []
        for skeleton in skeletons.sorted() {
            for (name, paths) in Self.clipCandidates(skeleton) {
                let line = Self.check(skeleton: skeleton, clip: name, paths: paths, files: files)
                lines.append(line.text)
                if !line.passed {
                    failures.append(line.text)
                }
            }
        }
        let dir = try RepositoryLogs.createdDirectory("creature-clips")
        try lines.joined(separator: "\n").write(
            to: dir.appending(path: "clips.txt"), atomically: true, encoding: .utf8
        )
        #expect(skeletons.count >= 40, "see \(dir.path)/clips.txt")
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    /// Skeleton mesh paths of every RACE whose skeleton is a creature with a rig beside it.
    private static func creatureSkeletons(
        root: GameDataRoot, files: VirtualFileSystem
    ) throws -> Set<String> {
        let races = try VanillaMasters.liveRecords(of: "RACE", in: VanillaMasters.load(root: root))
            .compactMap { try? Race(record: $0.record, localized: $0.localized) }
        let paths = races.flatMap { [$0.maleSkeletonPath, $0.femaleSkeletonPath] }
            .compactMap { $0.flatMap { try? VirtualFileSystem.normalize($0) } }
            .map { $0.hasPrefix("meshes\\") ? $0 : "meshes\\" + $0 }
        return Set(paths.filter {
            CreatureClipNames.location(skeletonMeshPath: $0) != nil
                && files.exists(String($0.dropLast(4)) + ".hkx")
        })
    }

    private static func clipCandidates(_ skeleton: String) -> [(String, [String])] {
        [
            ("idle", ActorAnimationClipLoader.idleAnimationPaths(
                skeletonMeshPath: skeleton, female: false
            )),
            ("walk", ActorAnimationClipLoader.gaitAnimationPaths(
                .walk, skeletonMeshPath: skeleton, female: false
            )),
            ("run", ActorAnimationClipLoader.gaitAnimationPaths(
                .run, skeletonMeshPath: skeleton, female: false
            ))
        ]
    }

    private static func check(
        skeleton: String, clip name: String, paths: [String], files: VirtualFileSystem
    ) -> (text: String, passed: Bool) {
        guard let path = paths.first(where: files.exists) else {
            return ("[ERROR] \(skeleton) \(name): no candidate exists", false)
        }
        do {
            let clip = try ActorAnimationClipLoader.clip(
                skeletonMeshPath: skeleton,
                animationPath: path,
                readHKX: { try HKXFile(data: files.contents(forPath: $0)) }
            )
            let seconds = clip.animation.duration
            return ("[INFO] \(skeleton) \(name): \(path) \(seconds) s", seconds > 0)
        } catch {
            return ("[ERROR] \(skeleton) \(name): \(path) \(error)", false)
        }
    }
}
