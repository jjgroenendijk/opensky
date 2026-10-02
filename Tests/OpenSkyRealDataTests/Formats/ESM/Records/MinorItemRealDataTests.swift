// KEYM, SLGM, and APPA sweep over `Skyrim.esm` and the DLC masters: every record
// decodes, the totals are pinned, and the unread-field tally goes to `logs/`.
// Run with `make test-real T='MinorItemRealDataTests'`.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct MinorItemRealDataTests {
    private static let pluginNames = [
        "Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"
    ]

    private static let expectedTotals = ["KEYM": 377, "SLGM": 17, "APPA": 45]

    private struct Sweep {
        var records: [String: Int] = [:]
        var failures: [String] = []
        var skipped = ItemFieldTally()
        /// Editor ID to record type plus its decoded enum, such as "APPA expert".
        var editorIDs: [String: String] = [:]
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func decodesEveryKeySoulGemAndApparatus() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        var sweep = Sweep()
        for pluginName in Self.pluginNames {
            let file = try ESMFile(url: root.dataURL.appending(path: pluginName))
            try Self.sweep(file: file, localized: file.pluginHeader().isLocalized, into: &sweep)
        }

        #expect(sweep.failures.isEmpty, "records that threw: \(sweep.failures.prefix(5))")
        #expect(sweep.records == Self.expectedTotals, "record count drift")
        #expect(sweep.editorIDs["SoulGemBlack"] == "SLGM empty/grand")
        #expect(sweep.editorIDs["SoulGemPettyFilled"] == "SLGM petty/petty")
        #expect(sweep.editorIDs["WhiterunJailKey"] == "KEYM")
        #expect(sweep.editorIDs["Alembic04Expert"] == "APPA expert")

        let unread = sweep.skipped.ranked.map { "  \($0.name): \($0.count)" }
        let report = ([
            "[INFO] records \(sweep.records.sorted { $0.key < $1.key })",
            "[INFO] unread fields:"
        ] + unread).joined(separator: "\n")
        print(report)
        try? report.write(
            to: Self.logURL("minor-item-sweep.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Container CNTO stacks naming the three families now resolve to an item.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func containerStacksOfTheThreeFamiliesResolve() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let store = ItemDefinitionStore(file: file)
        let types = ESMWalk.recordTypeIndex(in: file)
        let families: Set<FourCC> = ["KEYM", "SLGM", "APPA"]

        let entries = store.containers.values.flatMap(\.entries).filter {
            types[$0.item.rawValue].map(families.contains) ?? false
        }
        let unresolved = entries.filter { store.definition($0.item) == nil }
        #expect(!entries.isEmpty, "no CNTO names a key, soul gem, or apparatus")
        #expect(unresolved.isEmpty, "unresolved stacks: \(unresolved.prefix(5).map(\.item))")
        #expect(store.skippedCounts.values.reduce(0, +) == 0, "\(store.skippedCounts)")
        print("[INFO] Skyrim.esm CNTO naming KEYM/SLGM/APPA: \(entries.count), all resolve")
    }

    private static func sweep(file: ESMFile, localized: Bool, into sweep: inout Sweep) {
        var skipped = SkippedRecords()
        for type in expectedTotals.keys.sorted() {
            for record in file.liveRecords(of: FourCC(stringLiteral: type), skipped: &skipped) {
                sweep.records[type, default: 0] += 1
                do {
                    let decoded = try decode(record, localized: localized)
                    sweep.skipped.merge(decoded.skipped)
                    if let editorID = decoded.editorID {
                        sweep.editorIDs[editorID] = decoded.detail.map { "\(type) \($0)" } ?? type
                    }
                } catch {
                    sweep.failures.append("\(type) \(FormID(record.formID)): \(error)")
                }
            }
        }
    }

    private struct Decoded {
        let editorID: String?
        let detail: String?
        let skipped: ItemFieldTally
    }

    private static func decode(_ record: ESMRecord, localized: Bool) throws -> Decoded {
        switch record.type {
        case "KEYM":
            let key = try KeyItem(record: record, localized: localized)
            return Decoded(editorID: key.fields.editorID, detail: nil, skipped: key.skipped)
        case "SLGM":
            let gem = try SoulGem(record: record, localized: localized)
            let soul = "\(gem.containedSoul.map { "\($0)" } ?? "-")/"
                + "\(gem.capacity.map { "\($0)" } ?? "-")"
            return Decoded(editorID: gem.fields.editorID, detail: soul, skipped: gem.skipped)
        default:
            let apparatus = try Apparatus(record: record, localized: localized)
            return Decoded(
                editorID: apparatus.fields.editorID,
                detail: apparatus.quality.map { "\($0)" },
                skipped: apparatus.skipped
            )
        }
    }

    private static func logURL(_ name: String) throws -> URL {
        try RepositoryLogs.directory().appending(path: name)
    }
}
