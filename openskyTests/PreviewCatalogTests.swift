// Browse-model tests for main-app Asset Browser: category grouping, record
// rows, filtering. Synthetic entries + in-code plugin fixture only
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct PreviewCatalogTests {
    private var files: [VFSEntry] {
        [
            VFSEntry(path: "meshes\\clutter\\cup.nif", archive: "a.bsa"),
            VFSEntry(path: "sound\\fx\\door.wav", archive: "b.bsa"),
            VFSEntry(path: "textures\\clutter\\cup.dds", archive: "a.bsa")
        ]
    }

    private func makeRecords() throws -> [ESMRecord] {
        var plugin = ESMFixture.tes4()
        let stat = ESMFixture.record(
            "STAT",
            formID: 0x0000_ABCD,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestStatic"))
        )
        plugin += ESMFixture.topGroup("STAT", contents: stat)
        let file = try ESMFile(data: plugin)
        var records: [ESMRecord] = []
        ESMWalk.forEachRecord(in: file) { record in
            records.append(record)
            return true
        }
        return records
    }

    @Test func groupsFilesByExtension() throws {
        let catalog = try PreviewCatalog(files: files, records: makeRecords())
        #expect(catalog.items(for: .meshes).map(\.display) == ["meshes\\clutter\\cup.nif"])
        #expect(catalog.items(for: .textures).map(\.display) == ["textures\\clutter\\cup.dds"])
        #expect(catalog.items(for: .allFiles).count == 3)
        #expect(catalog.fileCount == 3)
        #expect(catalog.notes.isEmpty)
    }

    @Test func recordRowsShowTypeAndFormID() throws {
        let catalog = try PreviewCatalog(files: [], records: makeRecords())
        #expect(catalog.recordCount == 1)
        #expect(catalog.items(for: .records).map(\.display) == ["STAT 0000ABCD"])
    }

    @Test func filterIsCaseInsensitiveSubstring() {
        let catalog = PreviewCatalog(files: files, records: [])
        let all = catalog.items(for: .allFiles)
        #expect(PreviewCatalog.filter(all, query: "").count == 3)
        #expect(PreviewCatalog.filter(all, query: "  ").count == 3)
        #expect(PreviewCatalog.filter(all, query: "CUP").count == 2)
        #expect(PreviewCatalog.filter(all, query: "missing").isEmpty)
    }

    @Test func filterAcceptsForwardSlashes() {
        let catalog = PreviewCatalog(files: files, records: [])
        let all = catalog.items(for: .allFiles)
        let hits = PreviewCatalog.filter(all, query: "textures/clutter")
        #expect(hits.map(\.display) == ["textures\\clutter\\cup.dds"])
    }

    @Test func selectionCarriesTheEntry() {
        let catalog = PreviewCatalog(files: files, records: [])
        guard case let .file(entry)? = catalog.items(for: .meshes).first?.selection else {
            Issue.record("expected a file selection")
            return
        }
        #expect(entry.archive == "a.bsa")
    }
}
