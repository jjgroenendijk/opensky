// Env-gated node-class sweep over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md Legal & IP). Decodes every
// registered object of every behavior file under the character actor folder,
// third-person and `_1stperson`, and asserts the milestone's full-graph rule:
// every class those files declare has a decoder, every object of every such
// class decodes, and no member misreads its bytes.
//
// The report is class names and counts only and goes to gitignored `logs/`.
// Skips automatically when OPENSKY_DATA_ROOT is unset. Run with
// `make realtest T='HKBNodeDecodeRealDataTests/decodesEveryBehaviorNodeClass()'`.

import Foundation
@testable import opensky
import Testing

/// One behavior file's decode outcome plus where it came from, so a failure
/// names the file.
private struct DecodeRow {
    let path: String
    let report: HKBDecodeReport
    let rootGeneratorClassName: String?
    let topologyNodeCount: Int
}

struct HKBNodeDecodeRealDataTests {
    /// Real data only when explicitly pointed at via the env var, matching
    /// HKBBehaviorCensusRealDataTests, so machines without the override skip
    /// deterministically rather than falling back to the Steam default.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static let characterPrefix = "meshes\\actors\\character\\"

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesEveryBehaviorNodeClass() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let paths = vfs.archiveEntries()
            .map(\.path)
            .filter { $0.hasPrefix(Self.characterPrefix) && $0.hasSuffix(".hkx") }
        #expect(!paths.isEmpty, "no character .hkx files found under \(Self.characterPrefix)")

        var rows: [DecodeRow] = []
        var failures: [String] = []
        for path in paths {
            do {
                let file = try HKXFile(data: vfs.contents(forPath: path))
                let graph = try HKXObjectGraph(file: file)
                // Behavior files are the ones the full-graph rule binds; the
                // animation and skeleton files under the same folder carry hka
                // classes this registry deliberately does not cover.
                guard let behavior = HKBBehaviorGraph.graphs(in: graph).first else {
                    continue
                }
                let topology = behavior.rootGenerator.map {
                    HKBGraphTopology.walk(from: $0, in: graph)
                }
                rows.append(DecodeRow(
                    path: path,
                    report: HKBDecodeReport.decodeAll(in: graph),
                    rootGeneratorClassName: behavior.rootGeneratorClassName,
                    topologyNodeCount: topology?.nodes.count ?? 0
                ))
            } catch {
                failures.append("\(path): \(String(describing: error))")
            }
        }
        #expect(failures.isEmpty, "parse failures: \(failures.prefix(5))")
        #expect(!rows.isEmpty, "no behavior-role files in the sweep")

        try write(report(rows))
        assertFullGraphCoverage(rows)
    }

    // MARK: - Assertions

    private func assertFullGraphCoverage(_ rows: [DecodeRow]) {
        // The milestone rule: a class present in a player behavior file without
        // a decoder is a failed sweep, not a tolerated tally entry.
        let uncovered = rows.flatMap { row in
            row.report.uncoveredClassNames.map { "\(row.path): \($0)" }
        }
        #expect(uncovered.isEmpty, "classes with no decoder: \(uncovered.prefix(10))")

        // A class with a decoder that still returned nil means a corrupt object
        // offset, which the container layer should have caught first.
        let failed = rows.flatMap { row in
            row.report.failedCounts.map { "\(row.path): \($0.key) x\($0.value)" }
        }
        #expect(failed.isEmpty, "objects that failed to decode: \(failed.prefix(10))")

        for row in rows {
            #expect(row.report.decodedTotal > 0, "\(row.path) decoded nothing")
            #expect(
                row.rootGeneratorClassName == "hkbStateMachine",
                "\(row.path) root generator is \(row.rootGeneratorClassName ?? "<none>")"
            )
            #expect(row.topologyNodeCount > 0, "\(row.path) walked to no nodes")
        }

        // Unresolved fields are recorded rather than thrown, so they are the
        // signal that a member offset is wrong. `noFixup` is not that signal —
        // Havok writes a null pointer for an absent optional, and most nodes
        // carry no variable binding set. Every other miss means a decoder read
        // the wrong bytes, so those must be zero across the whole set.
        let misreads = rows.flatMap { row in
            row.report.unresolved
                .filter { $0.miss != .noFixup }
                .map { "\(row.path): \($0.field) \($0.miss.rawValue)" }
        }
        #expect(misreads.isEmpty, "misread members: \(misreads.prefix(10))")
    }

    // MARK: - Report

    private func report(_ rows: [DecodeRow]) -> String {
        var counts: [String: Int] = [:]
        var files: [String: Int] = [:]
        for row in rows {
            for (name, count) in row.report.decodedCounts {
                counts[name, default: 0] += count
                files[name, default: 0] += 1
            }
        }
        let decodedTotal = rows.reduce(0) { $0 + $1.report.decodedTotal }
        var lines = [
            "OpenSky behavior node decode — \(rows.count) behavior files, "
                + "\(decodedTotal) objects decoded",
            "",
            "## Decoded classes (objects, files)"
        ]
        lines += counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
            .map { "\($0.name) \($0.count) \(files[$0.name] ?? 0)" }
        lines += ["", "## Per file"]
        for row in rows.sorted(by: { $0.path < $1.path }) {
            lines.append("\(row.path): \(row.report.decodedTotal) objects, "
                + "\(row.topologyNodeCount) reachable nodes, "
                + "root \(row.rootGeneratorClassName ?? "<none>")")
        }
        let noFixupCount = rows.reduce(0) { total, row in
            total + row.report.unresolved.count { $0.miss == .noFixup }
        }
        let misreadCount = rows.reduce(0) { total, row in
            total + row.report.unresolved.count { $0.miss != .noFixup }
        }
        lines += [
            "",
            "## Unresolved",
            "noFixup (absent optional, expected): \(noFixupCount)",
            "other misses: \(misreadCount)"
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    private func write(_ report: String) throws {
        let url = logsDirectory.appending(path: "hkx-behavior-nodes.log")
        try FileManager.default.createDirectory(
            at: logsDirectory, withIntermediateDirectories: true
        )
        try report.write(to: url, atomically: true, encoding: .utf8)
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
    }
}
