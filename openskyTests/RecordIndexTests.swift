// Cross-plugin identity and precedence over synthetic ESM fixtures only.

import Foundation
@testable import opensky
import Testing

struct RecordIndexTests {
    @Test
    func laterOverrideWinsByResolvedFormID() throws {
        let base = try plugin(records: [record("KYWD", formID: 0x42, editorID: "Base")])
        let override = try plugin(
            masters: ["Base.esm"],
            records: [record("KYWD", formID: 0x42, editorID: "Override")]
        )
        let index = RecordIndex(
            plugins: [("Base.esm", base), ("Patch.esp", override)],
            recordTypes: ["KYWD"]
        )

        let entry = try indexedRecord(
            ResolvedFormID(plugin: "Base.esm", objectID: 0x42),
            in: index
        )
        #expect(entry.sourcePlugin == "Patch.esp")
        #expect(ESMWalk.editorID(of: entry.record) == "Override")
    }

    @Test
    func deletedAndMalformedOverridesPreserveEarlierValidRecord() throws {
        let base = try plugin(records: [record("KYWD", formID: 7, editorID: "Valid")])
        let deleted = try plugin(
            masters: ["Base.esm"],
            records: [record("KYWD", formID: 7, editorID: "Deleted", flags: 1 << 5)]
        )
        let malformed = try plugin(
            masters: ["Base.esm"],
            records: [ESMFixture.record("KYWD", formID: 7, data: Data([1]))]
        )
        let index = RecordIndex(
            plugins: [
                ("Base.esm", base),
                ("Delete.esp", deleted),
                ("Broken.esp", malformed)
            ],
            recordTypes: ["KYWD"]
        )

        let entry = try indexedRecord(
            ResolvedFormID(plugin: "Base.esm", objectID: 7),
            in: index
        )
        #expect(entry.sourcePlugin == "Base.esm")
    }

    @Test
    func typeSpecificDecodeFallsBackAndDistinguishesFailureFromMissing() throws {
        let base = try plugin(records: [record("KYWD", formID: 8, editorID: "Usable")])
        let override = try plugin(
            masters: ["Base.esm"],
            records: [record("KYWD", formID: 8, editorID: "Rejected")]
        )
        let index = RecordIndex(
            plugins: [("Base.esm", base), ("Patch.esp", override)],
            recordTypes: ["KYWD"]
        )
        let id = ResolvedFormID(plugin: "Base.esm", objectID: 8)

        let fallback = index.decode(id) { record in
            let editorID = ESMWalk.editorID(of: record)
            guard editorID != "Rejected", let editorID else {
                throw ESMError.malformed("synthetic body rejection")
            }
            return editorID
        }
        guard case let .decoded(value, sourcePlugin) = fallback else {
            Issue.record("expected the earlier decodable definition")
            return
        }
        #expect(value == "Usable")
        #expect(sourcePlugin == "Base.esm")

        let undecodable = index.decode(id) { _ -> String in
            throw ESMError.malformed("all candidates rejected")
        }
        guard case let .undecodable(failedID) = undecodable else {
            Issue.record("expected undecodable rather than missing")
            return
        }
        #expect(failedID == id)

        let absent = ResolvedFormID(plugin: "Base.esm", objectID: 999)
        let missing = index.decode(absent) { _ in "unused" }
        guard case let .missing(missingID) = missing else {
            Issue.record("expected missing for a dangling identity")
            return
        }
        #expect(missingID == absent)
    }

    @Test
    func sameRawFormIDInTwoPluginsMeansDifferentRecords() throws {
        let first = try plugin(records: [record("KYWD", formID: 9, editorID: "First")])
        let second = try plugin(records: [record("KYWD", formID: 9, editorID: "Second")])
        let index = RecordIndex(
            plugins: [("First.esm", first), ("Second.esp", second)],
            recordTypes: ["KYWD"]
        )

        let firstEntry = try indexedRecord(
            ResolvedFormID(plugin: "First.esm", objectID: 9),
            in: index
        )
        let secondEntry = try indexedRecord(
            ResolvedFormID(plugin: "Second.esp", objectID: 9),
            in: index
        )
        #expect(ESMWalk.editorID(of: firstEntry.record) == "First")
        #expect(ESMWalk.editorID(of: secondEntry.record) == "Second")
    }

    @Test
    func resolutionAndDanglingLookupAreExplicit() throws {
        let file = try plugin(
            masters: ["BASE.ESM"],
            records: [record("KYWD", formID: 0x0100_0001, editorID: "Own")]
        )
        let base = try plugin(records: [record("KYWD", formID: 3, editorID: "Base")])
        let index = RecordIndex(
            plugins: [("Base.esm", base), ("Child.esp", file)],
            recordTypes: ["KYWD"]
        )

        #expect(index.resolve(FormID(0), fromPlugin: "Child.esp") == .nullReference)
        #expect(
            index.resolve(FormID(3), fromPlugin: "CHILD.ESP")
                == .resolved(ResolvedFormID(plugin: "Base.esm", objectID: 3))
        )
        #expect(
            index.resolve(FormID(3), fromPlugin: "Absent.esp")
                == .unavailablePlugin("Absent.esp")
        )
        let missing = ResolvedFormID(plugin: "Base.esm", objectID: 999)
        guard case let .missing(actual) = index.lookup(missing) else {
            Issue.record("expected an explicit missing result")
            return
        }
        #expect(actual == missing)
    }

    @Test
    func unreadableActivePluginIsSkippedWithoutLosingTheRest() throws {
        let install = FileManager.default.temporaryDirectory
            .appending(path: "record-index-\(UUID().uuidString)", directoryHint: .isDirectory)
        let data = install.appending(path: "Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: install) }

        try pluginData(records: [record("KYWD", formID: 1, editorID: "Base")])
            .write(to: data.appending(path: "Skyrim.esm"))
        try Data([0, 1, 2]).write(to: data.appending(path: "Update.esm"))
        try pluginData(
            masters: ["Skyrim.esm", "Update.esm"],
            records: [record("KYWD", formID: 0x0200_0002, editorID: "DLC")]
        )
        .write(to: data.appending(path: "Dawnguard.esm"))

        let root = GameDataRoot(installURL: install, dataURL: data, source: .environment)
        let index = RecordIndexLoader.load(root: root, recordTypes: ["KYWD"])

        #expect(index.count(of: "KYWD") == 2)
        _ = try indexedRecord(ResolvedFormID(plugin: "Skyrim.esm", objectID: 1), in: index)
        _ = try indexedRecord(ResolvedFormID(plugin: "Dawnguard.esm", objectID: 2), in: index)
    }

    private func indexedRecord(
        _ id: ResolvedFormID,
        in index: RecordIndex
    ) throws -> IndexedRecord {
        guard case let .record(entry) = index.lookup(id) else {
            throw ESMError.malformed("fixture record missing from index: \(id)")
        }
        return entry
    }

    private func plugin(masters: [String] = [], records: [Data]) throws -> ESMFile {
        try ESMFile(data: pluginData(masters: masters, records: records))
    }

    private func pluginData(masters: [String] = [], records: [Data]) -> Data {
        ESMFixture.tes4(masters: masters)
            + ESMFixture.topGroup("KYWD", contents: records.reduce(Data(), +))
    }

    private func record(
        _ type: String,
        formID: UInt32,
        editorID: String,
        flags: UInt32 = 0
    ) -> Data {
        ESMFixture.record(
            type,
            formID: formID,
            flags: flags,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        )
    }
}
