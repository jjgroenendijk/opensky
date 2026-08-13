// Env-gated `.lip` sweep over every embedded payload in the user's read-only
// vanilla voice archives. Only derived counts leave the parser; no game bytes
// are copied into the repository or test products.

import Foundation
@testable import opensky
import Testing

struct LipSyncRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func parsesEveryEmbeddedLipTrack() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let paths = vfs.archiveEntries().map(\.path).filter { $0.hasSuffix(".fuz") }
        var lipBlobCount = 0
        var lipCount = 0
        var keyCount = 0
        var duplicateCount = 0
        var markerCount = 0
        var unmappedKeyCount = 0
        var firstFrames: [Int: Int] = [:]
        var unknownValues: [UInt16: Int] = [:]
        var layouts: [String: Int] = [:]
        var failureTallies: [String: Int] = [:]
        var failureExamples: [String] = []

        for path in paths {
            do {
                let container = try FUZFile(data: vfs.contents(forPath: path))
                guard let lipData = container.lipData else { continue }
                lipBlobCount += 1
                let lip = try LIPFile(data: lipData)
                lipCount += 1
                keyCount += lip.keys.count
                duplicateCount += lip.duplicateValueCount
                markerCount += lip.markerCount
                unmappedKeyCount += lip.unmappedKeyCount
                firstFrames[lip.header.firstFrame, default: 0] += 1
                unknownValues[lip.header.unknownValue, default: 0] += 1
                layouts[
                    "header \(lip.header.headerSize)B tuple \(lip.header.tupleWidth) "
                        + "vocab \(lip.header.targetCount) "
                        + "stride \(lip.header.slotsPerFrame)", default: 0
                ] += 1
                // Spelled as an explicit closure rather than a key path: the
                // `#expect` expansion of `allSatisfy(\.isFinite)` inside a
                // `do`/`catch` is read as a throwing call the enclosing context
                // does not handle, and the build fails (Swift 6.3.3).
                let finite = lip.sample(at: lip.duration / 2).weightsBySlot.values
                    .allSatisfy(\.isFinite)
                #expect(finite)
            } catch {
                let category = Self.failureCategory(error)
                failureTallies[category, default: 0] += 1
                if failureExamples.count < 5 {
                    failureExamples.append("\(path): \(String(describing: error))")
                }
            }
        }

        #expect(lipBlobCount == 74070, "embedded lip count drifted to \(lipBlobCount)")
        // 70,926 decoded on 2026-08-12, the first sweep after issue #449 taught
        // the decoder the alternate header family, the tick-derived slot stride
        // and the ambiguous marker framing. It was 61,484 before.
        #expect(lipCount > 70000, "only \(lipCount) tracks decoded")
        let failureCount = failureTallies.values.reduce(0, +)
        #expect(lipCount + failureCount == lipBlobCount)
        let report = """
        [INFO] lip sweep: \(paths.count) FUZ entries, \(lipBlobCount) lip blobs, \
        \(lipCount) standard tracks decoded, \(failureCount) typed parse failures
        [INFO] lip tokens: \(keyCount) keys, \(duplicateCount) duplicates, \
        \(markerCount) markers, \(unmappedKeyCount) keys in unmapped slots
        [INFO] lip layouts: \(Self.histogram(layouts))
        [INFO] lip first frames: \(Self.histogram(firstFrames))
        [INFO] lip unknown header values: \(Self.histogram(unknownValues))
        [INFO] lip failure categories: \(Self.histogram(failureTallies))
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

    private static func failureCategory(_ error: Error) -> String {
        guard let lipError = error as? LIPError else {
            return "container: \(String(describing: type(of: error)))"
        }
        switch lipError {
        case let .unsupported(reason):
            return "unsupported: \(reason)"
        case let .malformed(reason):
            if reason.hasPrefix("non-finite") {
                return "malformed: non-finite token"
            }
            if reason.hasPrefix("curve stream overruns") {
                return "malformed: terminal overrun"
            }
            if reason.hasPrefix("curve position") {
                return "malformed: grid overrun"
            }
            if reason.contains("trailing payload bytes") {
                return "malformed: trailing bytes"
            }
            return "malformed: \(reason)"
        }
    }

    private static func writeReport(_ report: String) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs/lip-sweep", directoryHint: .isDirectory)
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
