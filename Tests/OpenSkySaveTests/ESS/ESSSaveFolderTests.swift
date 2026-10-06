// The saves folder setting: each status message, listings newest first with a broken
// file kept as an error row, the thumbnail size, and the inspector sections.

import FormatsTesting
import Foundation
import OpenSkyFormatsESS
@testable import OpenSkySave
import Testing

struct ESSSaveFolderTests {
    private static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ess-folder-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func statusCoversEachFolderState() throws {
        #expect(ESSSaveFolder.status(of: nil) == .notSet)
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.path(percentEncoded: false)
        #expect(ESSSaveFolder
            .status(of: directory.appending(path: "gone")) == .missing(path + "gone"))
        try Data("x".utf8).write(to: directory.appending(path: "notes.txt"))
        #expect(ESSSaveFolder.status(of: directory) == .empty(path))
        #expect(ESSSaveFolder.status(of: directory).message.contains("no .ess files"))
        try ESSFixture().build().write(to: directory.appending(path: "Save1.ess"))
        #expect(ESSSaveFolder.status(of: directory) == .ready(path, count: 1))
    }

    @Test func listingsAreNewestFirstAndKeepBrokenFiles() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var older = ESSFixture()
        older.playerName = "Older"
        let olderURL = directory.appending(path: "Save1.ess")
        try older.build().write(to: olderURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: olderURL.path
        )
        try ESSFixture().build().write(to: directory.appending(path: "Save2.ESS"))
        try Data("TESV_BROKEN".utf8).write(to: directory.appending(path: "Broken.ess"))
        let listings = try ESSSaveFolder(directory: directory).listings()
        #expect(listings.count == 3)
        #expect(listings.last?.summary?.header.playerName == "Older")
        let broken = try #require(listings.first { $0.name == "Broken" })
        #expect(broken.summary == nil)
        #expect(broken.error != nil)
    }

    @Test func thumbnailShrinksByWholeSteps() throws {
        var fixture = ESSFixture()
        fixture.screenshotSize = (width: 1200, height: 600)
        let file = try ESSFile(data: fixture.build())
        let thumbnail = try #require(ESSSaveFolder.thumbnail(of: file.screenshot))
        #expect(thumbnail.width == 400)
        #expect(thumbnail.height == 200)
        #expect(thumbnail.rgba.count == 400 * 200 * 4)
    }

    @Test func inspectionListsEverySection() throws {
        let file = try ESSFile(data: ESSImportSaveFixture.save())
        let inspection = ESSInspection(
            file: file, currentPlugins: ["Skyrim.esm"], records: ESSImportSaveFixture.records
        )
        #expect(inspection.sections.map(\.title) == [
            "Header", "Plugins", "Sections", "Global data", "Change forms", "Papyrus",
            "Import report"
        ])
        #expect(inspection.text.contains("Prisoner"))
        #expect(inspection.report?.category("quests")?.imported == 1)
    }
}
