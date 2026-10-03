// Every archived `.hkt` on the install decodes as a Havok binary tagfile. The
// census pins the totals and shows that no file holds a cloth class. The class
// table goes to `logs/`; it holds names and counts only.

import Foundation
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyGameData
import Testing

struct HKTagfileRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func decodesEveryTagfileWithNoClothClass() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let paths = vfs.archiveEntries().map(\.path).filter { $0.hasSuffix(".hkt") }.sorted()
        var censuses: [HKTCensus] = []
        var failures: [String] = []
        var lines: [String] = []
        for path in paths {
            do {
                let census = try HKTCensus(file: HKTagfile(data: vfs.contents(forPath: path)))
                censuses.append(census)
                lines.append("\(path): v\(census.version), \(census.objectCount) objects, "
                    + "bones \(census.skeletonBones.joined(separator: " "))")
            } catch {
                failures.append("\(path): \(error)")
            }
        }
        var versions: [HKTCensus.ClassVersion: Int] = [:]
        for census in censuses {
            census.definitions.forEach { versions[$0, default: 0] += 1 }
        }
        lines += versions.keys.sorted().map { "\($0.name) v\($0.version): \(versions[$0] ?? 0)" }
        try lines.joined(separator: "\n").write(
            to: RepositoryLogs.directory().appending(path: "hkt-census.log"),
            atomically: true,
            encoding: .utf8
        )
        #expect(failures.isEmpty, "\(failures)")
        #expect(paths.count == 30)
        #expect(censuses.map(\.objectCount).reduce(0, +) == 777)
        #expect(versions.count == 121)
        let withoutEnd = censuses.count { !$0.hasEndTag }
        let fileVersions = Set(censuses.map(\.version))
        let clothClasses = censuses.flatMap(\.clothClasses)
        #expect(withoutEnd == 4)
        #expect(fileVersions == [0, 3])
        #expect(clothClasses.isEmpty)
        #expect(censuses.map(\.skeletonBones.count).reduce(0, +) == 34)
    }
}
