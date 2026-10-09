// The launcher's Continue button over save folders written in code: the newest
// save wins, and each reason the button is disabled.

import Foundation
@testable import OpenSkySave
import OpenSkySaveFixtures
import Testing

struct ContinueOfferTests {
    private struct Folder {
        let store: OpenSkySaveStore

        init() throws {
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "continue-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            store = OpenSkySaveStore(directory: directory)
        }

        func save(_ slot: String, name: String, level: Int, minutesAgo: Double) throws {
            let url = try store.save(
                snapshot: OpenSkySaveFixture.richSnapshot(),
                fingerprint: OpenSkySaveFixture.fingerprint,
                metadata: OpenSkySaveFixture.metadata,
                summary: SaveSummary(
                    characterName: name, level: level, raceName: "Nord",
                    locationName: "Whiterun", playSeconds: 60
                ),
                toSlot: slot
            )
            try date(url, minutesAgo: minutesAgo)
        }

        func corrupt(_ slot: String, minutesAgo: Double) throws {
            let url = try store.url(forSlot: slot)
            try Data("not a save".utf8).write(to: url)
            try date(url, minutesAgo: minutesAgo)
        }

        private func date(_ url: URL, minutesAgo: Double) throws {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -minutesAgo * 60)],
                ofItemAtPath: url.path(percentEncoded: false)
            )
        }

        func offer() throws -> ContinueOffer {
            try ContinueOffer(listings: store.listings())
        }

        func remove() {
            try? FileManager.default.removeItem(at: store.directory)
        }
    }

    @Test func theNewestSaveIsOffered() throws {
        let folder = try Folder()
        defer { folder.remove() }
        try folder.save("Save1", name: "Lydia", level: 3, minutesAgo: 30)
        try folder.save("Save2", name: "Lydia", level: 12, minutesAgo: 5)
        try folder.save("quicksave", name: "Lydia", level: 11, minutesAgo: 10)
        let offer = try folder.offer()
        #expect(offer.slot == "Save2")
        #expect(offer.isEnabled)
        #expect(offer.title == "Lydia, level 12, Whiterun")
        #expect(offer.disabledReason == nil)
        #expect(offer.date != nil)
    }

    @Test func noSavesDisablesContinue() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let offer = try folder.offer()
        #expect(!offer.isEnabled)
        #expect(offer.disabledReason == "No saves yet")
    }

    @Test func anUnreadableNewestSaveDisablesContinue() throws {
        let folder = try Folder()
        defer { folder.remove() }
        try folder.save("Save1", name: "Lydia", level: 3, minutesAgo: 30)
        try folder.corrupt("Save2", minutesAgo: 1)
        let offer = try folder.offer()
        #expect(!offer.isEnabled)
        #expect(offer.disabledReason == "The newest save, Save2, cannot be read")
    }

    @Test func aSaveWithoutASummaryShowsItsSlot() {
        let listing = OpenSkySaveSlotListing(
            slot: "old", modified: Date(),
            summary: OpenSkySaveSummaryFile(
                metadata: OpenSkySaveFixture.metadata, summary: nil, thumbnail: nil
            ),
            error: nil
        )
        let offer = ContinueOffer(listings: [listing])
        #expect(offer.slot == "old")
        #expect(offer.title == "old")
    }
}
