// Env-gated behavior census over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md Legal & IP). Sweeps every `.hkx`
// under the character actor folder, third-person and `_1stperson`, asserts the
// container parses with zero throws, and reports role, class signature,
// variable and event inventories, and referenced file names. The report is
// counts, names, and paths only and goes to gitignored `logs/`; nothing
// extracted from the install enters the repository.
//
// This census fixes the class list item 14.2 (#329) must decode and the
// variable and event names item 14.5 binds to. Skips automatically when
// OPENSKY_DATA_ROOT is unset or unresolvable. Run with
// `make realtest T='HKBBehaviorCensusRealDataTests/censusesCharacterBehaviorFiles()'`.

import Foundation
@testable import opensky
import Testing

/// One file's census plus where it came from, so the report is greppable by
/// path and the assertions can pick out the graph-role files.
private struct CensusRow {
    let path: String
    let census: HKBBehaviorCensus
}

struct HKBBehaviorCensusRealDataTests {
    /// Real data only when explicitly pointed at via the env var; the
    /// locator's Steam-default fallback is deliberately not consulted so
    /// machines without the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// Both player behavior sets live under this prefix; `_1stperson` is a
    /// subfolder of it, so one prefix covers third and first person.
    private static let characterPrefix = "meshes\\actors\\character\\"

    @Test(.enabled(if: Self.dataRoot != nil))
    func censusesCharacterBehaviorFiles() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let paths = vfs.archiveEntries()
            .map(\.path)
            .filter { $0.hasPrefix(Self.characterPrefix) && $0.hasSuffix(".hkx") }
        #expect(!paths.isEmpty, "no character .hkx files found under \(Self.characterPrefix)")

        var rows: [CensusRow] = []
        var failures: [String] = []
        for path in paths {
            do {
                let file = try HKXFile(data: vfs.contents(forPath: path))
                // The sweep asserts the SSE packfile profile rather than
                // assuming it: a tagfile or a different Havok version would
                // need a second container parser, which is out of scope for
                // 14.1 and must be re-scoped on the issue if it ever appears.
                #expect(file.header.versionString == "hk_2010.2.0-r1", "\(path)")
                #expect(file.header.pointerSize == 8, "\(path)")
                try rows.append(CensusRow(path: path, census: HKBBehaviorCensus.census(of: file)))
            } catch {
                failures.append("\(path): \(String(describing: error))")
            }
        }
        #expect(failures.isEmpty, "container parse failures: \(failures.prefix(5))")

        try write(report(rows))
        assertInventories(rows)
    }

    // MARK: - Assertions

    /// The acceptance: every role is represented, and the graph-role files
    /// carry non-empty class, variable, and event inventories.
    private func assertInventories(_ rows: [CensusRow]) {
        let byRole = Dictionary(grouping: rows) { $0.census.role }
        #expect(byRole[.project]?.isEmpty == false, "no project file in the sweep")
        #expect(byRole[.character]?.isEmpty == false, "no character file in the sweep")
        #expect(byRole[.behavior]?.isEmpty == false, "no behavior file in the sweep")

        for row in byRole[.behavior] ?? [] {
            #expect(!row.census.classCounts.isEmpty, "\(row.path) has no class inventory")
            #expect(row.census.graphName != nil, "\(row.path) has no graph name")
            #expect(
                row.census.rootGeneratorClassName != nil,
                "\(row.path) has no root generator class"
            )
        }
        // Every variable and event name in the set comes from the behavior
        // files, so the union is what 14.2 and 14.5 key on.
        let variables = Set((byRole[.behavior] ?? []).flatMap(\.census.variableNames))
        let events = Set((byRole[.behavior] ?? [])
            .flatMap { $0.census.eventNames.compactMap(\.self) })
        #expect(!variables.isEmpty, "no variable names across the behavior files")
        #expect(!events.isEmpty, "no event names across the behavior files")

        for row in byRole[.character] ?? [] {
            #expect(
                !row.census.referencedBehaviorFiles.isEmpty,
                "\(row.path) names no behavior file"
            )
            #expect(
                !row.census.referencedAnimationFiles.isEmpty,
                "\(row.path) names no animation clips"
            )
        }
        // Unresolved fields are recorded rather than thrown, so they are the
        // signal that a member offset is wrong. A `noFixup` miss is not that
        // signal — Havok writes a null pointer for an absent optional, and the
        // first-person character files legitimately carry no `m_ragdollName`.
        // Every other miss means the decoder read the wrong bytes, so those
        // must be zero across the whole install.
        let misreads = rows.flatMap { row in
            row.census.unresolved
                .filter { $0.miss != .noFixup }
                .map { "\(row.path): \($0.field) \($0.miss.rawValue)" }
        }
        #expect(misreads.isEmpty, "misread members: \(misreads.prefix(5))")
    }

    // MARK: - Report

    private func report(_ rows: [CensusRow]) -> String {
        var lines = [
            "OpenSky behavior census — \(rows.count) .hkx files under \(Self.characterPrefix)",
            ""
        ]
        lines += roleSummary(rows)
        lines.append("")
        lines += classSignature(rows)
        lines.append("")
        for row in rows where row.census.role != .animation {
            lines += fileReport(row)
        }
        lines += behaviorNameUnion(rows)
        return lines.joined(separator: "\n") + "\n"
    }

    private func roleSummary(_ rows: [CensusRow]) -> [String] {
        let byRole = Dictionary(grouping: rows) { $0.census.role }
        return ["## Roles"] + byRole
            .map { "\($0.key.rawValue): \($0.value.count)" }
            .sorted()
    }

    /// Class-name signature across the graph-role files: what item 14.2 has to
    /// decode, in the order the count justifies.
    private func classSignature(_ rows: [CensusRow]) -> [String] {
        var counts: [String: Int] = [:]
        var files: [String: Int] = [:]
        for row in rows where row.census.role == .behavior {
            for (name, count) in row.census.classCounts {
                counts[name, default: 0] += count
                files[name, default: 0] += 1
            }
        }
        let ordered = counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        return ["## Class signature across behavior files (objects, files)"]
            + ordered.map { "\($0.name) \($0.count) \(files[$0.name] ?? 0)" }
    }

    private func fileReport(_ row: CensusRow) -> [String] {
        var lines = ["## \(row.path)", "role: \(row.census.role.rawValue)"]
        lines.append("objects: \(row.census.objectCount)")
        if let name = row.census.graphName {
            lines.append("graph: \(name)")
        }
        if let generator = row.census.rootGeneratorClassName {
            lines.append("root generator: \(generator)")
        }
        if !row.census.variables.isEmpty {
            lines.append("variables: \(row.census.variables.count)")
            lines += row.census.variables.map {
                "  \($0.name ?? "<unnamed>") : "
                    + ($0.type?.description ?? "raw \($0.rawType)")
            }
        }
        lines += list("events", row.census.eventNames.compactMap(\.self))
        lines += list("character properties", row.census.characterPropertyNames.compactMap(\.self))
        lines += list("referenced behaviors", row.census.referencedBehaviorFiles)
        lines += list("referenced characters", row.census.referencedCharacterFiles)
        lines += list("referenced animations", row.census.referencedAnimationFiles)
        if !row.census.unresolved.isEmpty {
            lines.append("unresolved: \(row.census.unresolved.count)")
            lines += row.census.unresolved.map { "  \($0.field) \($0.miss.rawValue)" }
        }
        lines.append("")
        return lines
    }

    /// The de-duplicated name surface 14.5 binds engine state to.
    private func behaviorNameUnion(_ rows: [CensusRow]) -> [String] {
        let behaviors = rows.filter { $0.census.role == .behavior }
        let variables = Set(behaviors.flatMap(\.census.variableNames)).sorted()
        let events = Set(behaviors.flatMap { $0.census.eventNames.compactMap(\.self) }).sorted()
        return ["## Union across behavior files"]
            + list("distinct variables", variables)
            + list("distinct events", events)
    }

    private func list(_ label: String, _ values: [String]) -> [String] {
        guard !values.isEmpty else { return [] }
        return ["\(label): \(values.count)"] + values.map { "  \($0)" }
    }

    private func write(_ report: String) throws {
        let url = logsDirectory.appending(path: "hkx-behavior-census.log")
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
