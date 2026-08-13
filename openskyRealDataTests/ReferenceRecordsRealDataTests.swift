// Env-gated ECZN/COLL/DOBJ decode, store and DOBJ-tag census over the user's
// read-only install. No game-derived bytes leave the run.

import Foundation
@testable import opensky
import Testing

struct ReferenceRecordsRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty else {
            return nil
        }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesStoresAndEnumeratesEveryDefaultObjectRecord() throws {
        let root = try #require(Self.dataRoot)
        let index = RecordIndexLoader.load(root: root)
        let zoneStore = EncounterZoneStore(index: index)
        let layerStore = CollisionLayerStore(index: index)
        let defaultStore = DefaultObjectStore(index: index)

        #expect(index.collectedCount(of: "ECZN") >= 358)
        #expect(index.collectedCount(of: "COLL") >= 55)
        #expect(index.collectedCount(of: "DOBJ") >= 5)
        #expect(zoneStore.zones.count == index.count(of: "ECZN"))
        #expect(layerStore.layers.count >= 55)

        let bleakFalls = try #require(zoneStore.zone(editorID: "BleakFallsBarrowZone"))
        #expect(bleakFalls.id == ResolvedFormID(
            plugin: "Skyrim.esm", objectID: 0x038AB1
        ))
        #expect(bleakFalls.zone.minimumLevel != nil)

        let reports = try defaultObjectReports(root: root)
        #expect(reports.count >= 5)
        for report in reports {
            print(
                "[INFO] DOBJ \(report.plugin): \(report.entryCount) slots, "
                    + "tags [\(report.tags.sorted().joined(separator: ","))]"
            )
        }
        let actualTags = Set(reports.flatMap(\.tags))
        let unusedKnownTags = ["GCK8", "GCK9", "MHFL"]
            .compactMap(DefaultObjectTag.init(name:))
        let expectedTags = Set(DefaultObjectTag.knownMeanings.keys)
            .subtracting(unusedKnownTags.map(\.code))
        #expect(actualTags == Set(expectedTags.map(\.description)))
        #expect(defaultStore.entries.count == actualTags.count)
    }

    private func defaultObjectReports(root: GameDataRoot) throws -> [DefaultObjectReport] {
        var reports: [DefaultObjectReport] = []
        for plugin in ActivePluginFiles.load(root: root) {
            guard
                let group = plugin.file.topGroup(of: "DOBJ"),
                let children = try? group.children()
            else { continue }
            for case let .record(record) in children where !record.isDeleted {
                let defaults = try DefaultObjects(record: record)
                #expect(defaults.skipped.total == 0)
                try reports.append(DefaultObjectReport(
                    plugin: plugin.name,
                    entryCount: dnamEntryCount(record),
                    tags: defaults.entries.map(\.tag.description)
                ))
            }
        }
        return reports
    }

    private func dnamEntryCount(_ record: ESMRecord) throws -> Int {
        let field = try #require(try record.fields().first { $0.type == "DNAM" })
        #expect(field.data.count % 8 == 0)
        return field.data.count / 8
    }
}

private struct DefaultObjectReport {
    let plugin: String
    let entryCount: Int
    let tags: [String]
}
