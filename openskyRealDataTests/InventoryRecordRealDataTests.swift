// Env-gated inventory-record sweep over the user's own Skyrim SE install
// (read-only external input, never committed — AGENTS.md Legal & IP).
// Skips automatically when OPENSKY_DATA_ROOT is unset or unresolvable.
// Summaries print and are written to gitignored logs/. Run with
// `make realtest T=InventoryRecordRealDataTests/sweepsEveryInventoryRecord()`.

import Foundation
@testable import opensky
import Testing

struct InventoryRecordRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// Decodes every CONT, MISC, BOOK, ALCH, INGR, WEAP and AMMO record in
    /// Skyrim.esm with zero throws, then asserts the link invariants the
    /// inventory runtime depends on.
    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsEveryInventoryRecord() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let store = ItemDefinitionStore(file: file)

        // Zero throws: every family decoded, nothing skipped.
        let skipped = store.skippedCounts.values.reduce(0, +)
        #expect(skipped == 0, "records failed to decode: \(store.skippedCounts)")
        #expect(!store.definitions.isEmpty, "no carryable records in Skyrim.esm")
        #expect(!store.containers.isEmpty, "no CONT records in Skyrim.esm")

        // Every family Skyrim.esm ships must be present.
        for family in ItemDefinition.Family.allCases {
            #expect(
                !store.definitions(of: family).isEmpty,
                "no \(family.rawValue) records decoded"
            )
        }

        // Every CNTO target must resolve to a record of one of the types xEdit
        // constrains the slot to (wbCNTO, wbDefinitionsTES5.pas line 2315).
        // Anything else would mean the 8-byte CNTO layout is being misread —
        // this is the invariant that pins item-then-count rather than the
        // reverse. Only ARMO/AMMO/BOOK/ALCH/INGR/MISC/WEAP land in the item
        // index; the rest (APPA, KEYM, LIGH, SLGM, SCRL, LVLI) are legal
        // container contents whose own decoders are out of scope for #175.
        let contents = store.containers.values.flatMap(\.entries)
        let types = ESMWalk.recordTypeIndex(in: file)
        var unexpected: Set<String> = []
        for entry in contents {
            guard let type = types[entry.item.rawValue] else {
                unexpected.insert("(no such record)")
                continue
            }
            guard !Self.allowedContainerItemTypes.contains(type) else { continue }
            unexpected.insert(type.description)
        }
        #expect(unexpected.isEmpty, "container entries target \(unexpected.sorted())")

        let mismatched = store.containers.values.count(where: \.entryCountMismatch)
        #expect(mismatched == 0, "COCT disagrees with the CNTO fields decoded")

        let owned = Self.ownedReferenceCount(in: file)
        #expect(owned.owner > 0, "no XOWN found — ownership decode is not exercised")

        let summary = Self.summary(store: store, contents: contents, ownership: owned)
        print(summary)
        try? summary.write(to: Self.logURL, atomically: true, encoding: .utf8)
    }

    private static func summary(
        store: ItemDefinitionStore,
        contents: [Container.Entry],
        ownership: (owner: Int, count: Int)
    ) -> String {
        let perFamily = ItemDefinition.Family.allCases
            .map { "\($0.rawValue) \(store.definitions(of: $0).count)" }
            .joined(separator: ", ")
        let values = store.definitions.values.map(\.value)
        let weights = store.definitions.values.map(\.weight)
        return """
        [INFO] Skyrim.esm inventory sweep: \(store.definitions.count) items decoded \
        (\(perFamily)); skips \(store.skippedCounts.values.reduce(0, +))
        [INFO] containers: \(store.containers.count) CONT, \(contents.count) CNTO entries \
        (\(contents.count { store.definition($0.item) != nil }) resolve into the item index, \
        the rest are LVLI/KEYM/LIGH/SLGM/APPA/SCRL); \
        COCT mismatches \(store.containers.values.count(where: \.entryCountMismatch))
        [INFO] value range: \(values.min() ?? 0)...\(values.max() ?? 0); \
        weight range: \(weights.min() ?? 0)...\(weights.max() ?? 0)
        [INFO] placed references: \(ownership.owner) with XOWN, \(ownership.count) with XCNT
        """
    }

    /// Counts REFR ownership subrecords across every cell in the file. Walks
    /// records rather than cells so the sweep stays independent of the cell
    /// builder.
    private static func ownedReferenceCount(in file: ESMFile) -> (owner: Int, count: Int) {
        var owner = 0
        var count = 0
        ESMWalk.forEachRecord(in: file) { record in
            guard
                record.type == "REFR",
                let reference = try? PlacedReference(record: record)
            else { return true }
            if reference.owner != nil {
                owner += 1
            }
            if reference.itemCount != nil {
                count += 1
            }
            return true
        }
        return (owner, count)
    }

    /// The record types xEdit constrains a CNTO item slot to: `wbCNTO`,
    /// wbDefinitionsTES5.pas dev-4.1.6 line 2315.
    private static let allowedContainerItemTypes: Set<FourCC> = [
        "ARMO", "AMMO", "APPA", "MISC", "WEAP", "BOOK", "LVLI",
        "KEYM", "ALCH", "INGR", "LIGH", "SLGM", "SCRL"
    ]

    private static var logURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
            .appending(path: "inventory-sweep.log")
    }
}
