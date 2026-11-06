// A location clears itself when every boss it lists is dead or disabled
// (docs/formats/locations.md#cleared-locations), over synthetic LCTN and DOBJ records.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct LocationClearingTests {
    private static let bossType: UInt32 = 0x600
    private static let clearable: UInt32 = 0x900

    private static func store(keywords: [UInt32]) throws -> LocationStore {
        var dobj = Data()
        for (tag, object) in [("LRTB", bossType), ("KWDO", clearable)] {
            dobj.append(contentsOf: tag.utf8)
            dobj.appendUInt32(object)
        }
        let special = ESMFixture.words([bossType, 0x700, 0x3C, 0, bossType, 0x701, 0x3C, 0])
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("Barrow"))
            + ESMFixture.field("LCSR", special)
        if !keywords.isEmpty {
            fields += ESMFixture.field("KSIZ", ESMFixture.words([UInt32(keywords.count)]))
                + ESMFixture.field("KWDA", ESMFixture.words(keywords))
        }
        let data = ESMFixture.tes4()
            + ESMFixture.topGroup("DOBJ", contents: ESMFixture.record(
                "DOBJ", formID: 0x31, data: ESMFixture.field("DNAM", dobj)
            ))
            + ESMFixture.topGroup("LCTN", contents: ESMFixture.record(
                "LCTN", formID: 0x500, data: fields
            ))
        return try LocationStore(plugins: [("Test.esm", ESMFile(data: data))])
    }

    private static func key(_ id: UInt32) -> ReferenceKey {
        ReferenceKey(resolved: ResolvedFormID(plugin: "Test.esm", objectID: id))
    }

    @Test func theLastBossToDieClearsTheLocation() throws {
        let store = try Self.store(keywords: [Self.clearable])
        let barrow = ResolvedFormID(plugin: "Test.esm", objectID: 0x500)
        #expect(store.locationsCleared(byDeathOf: Self.key(0x700)) { _ in false }.isEmpty)
        let cleared = store.locationsCleared(byDeathOf: Self.key(0x701)) {
            $0 == Self.key(0x700)
        }
        #expect(cleared == [barrow])
        #expect(store.playsClearedMusic(barrow))
        #expect(store.locationsCleared(byDeathOf: Self.key(0x702)) { _ in true }.isEmpty)
    }

    /// The game counts a disabled boss as done once another boss dies.
    @Test func aDisabledBossCountsAsDoneWhenTheOtherDies() throws {
        let store = try Self.store(keywords: [Self.clearable])
        let disabled = Self.key(0x700)
        let cleared = store.locationsCleared(byDeathOf: Self.key(0x701)) { $0 == disabled }
        #expect(cleared == [ResolvedFormID(plugin: "Test.esm", objectID: 0x500)])
    }

    @Test func aLocationWithoutTheClearableKeywordClearsQuietly() throws {
        let store = try Self.store(keywords: [])
        #expect(!store.playsClearedMusic(ResolvedFormID(plugin: "Test.esm", objectID: 0x500)))
    }
}
