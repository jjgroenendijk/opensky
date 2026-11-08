// Env-gated `.lip` sweep over every embedded payload in the user's read-only
// vanilla voice archives. Only derived counts leave the parser; no game bytes
// are copied into the repository or test products.

import Foundation
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyFormatsAudio
@testable import OpenSkyGameData
import Testing

struct LipSyncRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func parsesEveryEmbeddedLipTrack() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let paths = vfs.archiveEntries().map(\.path).filter { $0.hasSuffix(".fuz") }
        var lipBlobCount = 0
        var lipCount = 0
        var layouts: [String: Int] = [:]
        var firstFrames: [Int: Int] = [:]
        var activeSlots: [Int: Int] = [:]
        var outOfRange = 0
        var failureTallies: [String: Int] = [:]
        var failureExamples: [String] = []

        for path in paths {
            do {
                let container = try FUZFile(data: vfs.contents(forPath: path))
                guard let lipData = container.lipData else { continue }
                lipBlobCount += 1
                let lip = try LIPFile(data: lipData)
                lipCount += 1
                layouts[
                    "targets \(lip.header.targetCount) stride \(lip.header.slotsPerFrame)",
                    default: 0
                ] += 1
                firstFrames[lip.header.firstFrame, default: 0] += 1
                for slot in lip.activeSlots {
                    activeSlots[slot, default: 0] += 1
                }
                outOfRange += lip.values.count { $0 < -1 || $0 > 2 }
            } catch {
                failureTallies[String(describing: error), default: 0] += 1
                if failureExamples.count < 5 {
                    failureExamples.append("\(path): \(String(describing: error))")
                }
            }
        }

        #expect(
            ContentCount.isNear(lipBlobCount, 74070),
            "embedded lip count drifted to \(lipBlobCount)"
        )
        // Every vanilla track decoded on 2026-10-15.
        #expect(lipCount == lipBlobCount, "only \(lipCount) tracks decoded")
        #expect(outOfRange == 0, "\(outOfRange) curve values outside -1...2")
        let failureCount = failureTallies.values.reduce(0, +)
        let report = """
        [INFO] lip sweep: \(paths.count) FUZ entries, \(lipBlobCount) lip blobs, \
        \(lipCount) tracks decoded, \(failureCount) typed parse failures
        [INFO] lip layouts: \(Self.histogram(layouts))
        [INFO] lip first frames: \(Self.histogram(firstFrames))
        [INFO] lip tracks per active slot: \(Self.histogram(activeSlots))
        [INFO] lip failures: \(Self.histogram(failureTallies))
        [INFO] lip failure examples: \(failureExamples.joined(separator: " | "))
        """
        print(report)
        try Self.writeReport(report)
    }

    private static func histogram(_ values: [some Comparable: Int]) -> String {
        values.sorted { $0.key < $1.key }
            .map { "\($0.key)x\($0.value)" }
            .joined(separator: " ")
    }

    private static func writeReport(_ report: String) throws {
        let root = try RepositoryLogs.directory("lip-sweep")
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let run = root.appending(path: stamp, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        try (report + "\n").write(
            to: run.appending(path: "sweep.txt"), atomically: true, encoding: .utf8
        )
        print("[INFO] lip sweep report: \(run.path())")
    }
}
