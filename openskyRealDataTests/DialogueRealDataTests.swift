// Env-gated DIAL/INFO/VTYP sweep over the user's read-only vanilla install.
// It decodes every matching record in Skyrim.esm and the three DLC masters,
// pins the record totals after the probe, and records every deliberately
// skipped field category in a gitignored per-run report.
//
// Since issue #426 the INFO VMAD fragment tail is decoded rather than skipped,
// so the `script INFO fragments` bucket is gone from the pinned tally and the
// sweep counts the decoded result scripts instead.

import Foundation
@testable import opensky
import Testing

struct DialogueRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static let pluginNames = [
        "Skyrim.esm",
        "Update.esm",
        "Dawnguard.esm",
        "HearthFires.esm",
        "Dragonborn.esm"
    ]

    private static let expectedRecords: [String: [String: Int]] = [
        "Skyrim.esm": ["DIAL": 15037, "INFO": 31465, "VTYP": 143],
        "Update.esm": ["DIAL": 90, "INFO": 139],
        "Dawnguard.esm": ["DIAL": 2038, "INFO": 3457, "VTYP": 21],
        "HearthFires.esm": ["DIAL": 482, "INFO": 1706],
        "Dragonborn.esm": ["DIAL": 2197, "INFO": 4421, "VTYP": 19]
    ]

    private static let expectedSkips = [
        "script alias object": 1365,
        "unknown NEXT": 861,
        "unknown QNAM": 1662,
        "unknown SCHR": 1722
    ]

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesVanillaDialogueRecordsWithoutFailures() throws {
        let root = try #require(Self.dataRoot)
        var total = Sweep()
        var pluginReports: [String] = []
        for pluginName in Self.pluginNames {
            let url = root.dataURL.appending(path: pluginName)
            let file = try ESMFile(url: url)
            let localized = try file.pluginHeader().isLocalized
            let sweep = Self.sweep(file: file, localized: localized)
            total.merge(sweep)
            pluginReports.append(sweep.report(name: pluginName))
            #expect(sweep.records == Self.expectedRecords[pluginName], "\(pluginName) count drift")

            let store = DialogueStore(
                file: file, pluginName: pluginName, localized: localized
            )
            #expect(store.skippedRecordCount == 0, "\(pluginName) store skipped records")
            if pluginName == "Skyrim.esm" {
                try checkDialogueStringTable(file: file, root: root)
            }
        }

        #expect(total.failures == 0, "dialogue records that threw: \(total.failures)")
        #expect(total.records["DIAL", default: 0] > 0)
        #expect(total.records["INFO", default: 0] > 0)
        #expect(total.records["VTYP", default: 0] > 0)
        #expect(total.skips == Self.expectedSkips, "dialogue skip tally drift")
        // Every tail the sweep used to skip now decodes, and each carries one
        // or two result-script fragments (issue #426).
        #expect(total.fragmentTails == 7661, "INFO fragment tail drift")
        #expect(total.fragments == 8009, "INFO fragment drift")

        let report = (pluginReports + [total.report(name: "TOTAL")])
            .joined(separator: "\n\n") + "\n"
        print(report)
        try writeReport(report)
    }

    private struct Sweep {
        var records: [String: Int] = [:]
        var skips: [String: Int] = [:]
        var failures = 0
        /// INFO records whose VMAD fragment tail decoded (issue #426).
        var fragmentTails = 0
        /// Result-script fragments across those tails.
        var fragments = 0

        mutating func merge(_ other: Sweep) {
            fragmentTails += other.fragmentTails
            fragments += other.fragments
            for (name, count) in other.records {
                records[name, default: 0] += count
            }
            for (name, count) in other.skips {
                skips[name, default: 0] += count
            }
            failures += other.failures
        }

        mutating func add(_ tally: DialogueTally) {
            for item in tally.ranked {
                skips[item.name, default: 0] += item.count
            }
        }

        mutating func add(_ tally: ScriptDataTally) {
            for item in tally.ranked {
                skips["script \(item.name)", default: 0] += item.count
            }
        }

        func report(name: String) -> String {
            let decoded = records.sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }.joined(separator: " ")
            let skipped = skips.sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }.joined(separator: ", ")
            return """
            [INFO] \(name): \(decoded); failures:\(failures)
            [INFO] INFO fragment tails:\(fragmentTails) fragments:\(fragments)
            [INFO] skipped: \(skipped.isEmpty ? "none" : skipped)
            """
        }
    }

    private static func sweep(file: ESMFile, localized: Bool) -> Sweep {
        var sweep = Sweep()
        ESMWalk.forEachRecord(in: file) { record in
            switch record.type {
            case "DIAL": decodeTopic(record, localized: localized, into: &sweep)
            case "INFO": decodeInfo(record, localized: localized, into: &sweep)
            case "VTYP": decodeVoice(record, into: &sweep)
            default: break
            }
            return true
        }
        return sweep
    }

    private static func decodeTopic(
        _ record: ESMRecord,
        localized: Bool,
        into sweep: inout Sweep
    ) {
        sweep.records["DIAL", default: 0] += 1
        do {
            try sweep.add(DialogueTopic(record: record, localized: localized).skipped)
        } catch {
            sweep.failures += 1
        }
    }

    private static func decodeInfo(
        _ record: ESMRecord,
        localized: Bool,
        into sweep: inout Sweep
    ) {
        sweep.records["INFO", default: 0] += 1
        do {
            let info = try TopicInfo(record: record, localized: localized)
            sweep.add(info.skipped)
            sweep.add(info.script.skipped)
            if info.script.infoFragments != nil {
                sweep.fragmentTails += 1
            }
            sweep.fragments += info.fragments.count
        } catch {
            sweep.failures += 1
        }
    }

    private static func decodeVoice(_ record: ESMRecord, into sweep: inout Sweep) {
        sweep.records["VTYP", default: 0] += 1
        do {
            try sweep.add(VoiceType(record: record).skipped)
        } catch {
            sweep.failures += 1
        }
    }

    /// Observed-table check for the issue-text/spec discrepancy: choose a
    /// shipped NAM1 ID and prove its text exists in ILSTRINGS, not DLSTRINGS.
    private func checkDialogueStringTable(file: ESMFile, root: GameDataRoot) throws {
        var sample: LString?
        ESMWalk.forEachRecord(in: file) { record in
            guard
                record.type == "INFO",
                let info = try? TopicInfo(record: record, localized: true),
                let text = info.responses.compactMap(\.text).first(where: {
                    if case let .tableID(id) = $0 {
                        return id != 0
                    }
                    return false
                })
            else { return true }
            sample = text
            return false
        }
        let text = try #require(sample, "Skyrim.esm has no localized INFO NAM1")
        let strings = LocalizedStrings(
            vfs: VirtualFileSystem(root: root),
            pluginName: "Skyrim.esm"
        )
        let dialogue = strings.resolve(text, kind: .ilstrings)
        let journal = strings.resolve(text, kind: .dlstrings)
        #expect(dialogue != nil, "INFO NAM1 did not resolve through ILSTRINGS")
        #expect(dialogue != journal, "INFO NAM1 also resolved to the DLSTRINGS entry")
    }

    private func writeReport(_ report: String) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs/dialogue-sweep", directoryHint: .isDirectory)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let run = root.appending(path: stamp, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        try report.write(
            to: run.appending(path: "report.txt"),
            atomically: true,
            encoding: .utf8
        )
        print("[INFO] dialogue sweep report: \(run.path())")
    }
}
