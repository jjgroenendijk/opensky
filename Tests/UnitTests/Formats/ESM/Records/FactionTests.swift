// Synthetic FACT layout coverage: every block the decoder reads, the tallies a
// malformed record produces, and the dump the CLI and Asset Browser print. No
// game-derived bytes.

import Foundation
@testable import opensky
import Testing

struct FactionTests {
    @Test
    func decodesEveryBlockOfAFullRecord() throws {
        var body = FactionFixture.relation(0x0100, modifier: -3, reaction: 1)
        body += FactionFixture.relation(0x0101, modifier: 0, reaction: 2)
        body += FactionFixture.flags(0x0000_4041)
        body += FactionFixture.link("JAIL", 0x0200)
        body += FactionFixture.link("WAIT", 0x0201)
        body += FactionFixture.link("STOL", 0x0202)
        body += FactionFixture.link("PLCN", 0x0203)
        body += FactionFixture.link("CRGR", 0x0204)
        body += FactionFixture.link("JOUT", 0x0205)
        body += FactionFixture.crimeValues()
        body += FactionFixture.rank(0, male: "Whelp", female: "Whelp")
        body += FactionFixture.rank(1, male: "Shield-Brother", female: "Shield-Sister")
        body += FactionFixture.link("VEND", 0x0300)
        body += FactionFixture.link("VENC", 0x0301)
        body += FactionFixture.vendorValues()
        body += FactionFixture.vendorLocation(type: 1, value: 0x0400, radius: -1)
        body += ESMFixture.field("CTDA", Data(count: 32))

        let faction = try Faction(
            record: FactionFixture.decode(FactionFixture.record(
                formID: 0x10,
                editorID: "TestFaction",
                name: "Test Faction",
                body: body
            )),
            localized: false
        )

        #expect(faction.formID == FormID(0x10))
        #expect(faction.editorID == "TestFaction")
        #expect(faction.name == LString.inline("Test Faction"))
        #expect(faction.displayName == "Test Faction")
        #expect(faction.flags == [.hiddenFromNPC, .trackCrime, .vendor])
        #expect(faction.isVendor)
        #expect(faction.tracksCrime)
        #expect(faction.exteriorJailMarker == FormID(0x0200))
        #expect(faction.followerWaitMarker == FormID(0x0201))
        #expect(faction.evidenceChest == FormID(0x0202))
        #expect(faction.playerInventoryContainer == FormID(0x0203))
        #expect(faction.sharedCrimeFactionList == FormID(0x0204))
        #expect(faction.jailOutfit == FormID(0x0205))
        #expect(faction.vendorBuySellList == FormID(0x0300))
        #expect(faction.merchantContainer == FormID(0x0301))
        #expect(faction.vendorLocation == Faction.VendorLocation(
            type: 1,
            value: 0x0400,
            radius: -1
        ))
        #expect(faction.vendorConditions.conditions.count == 1)
        #expect(faction.skipped.total == 0)
    }

    @Test
    func relationsRoundTripThroughEveryReactionIncludingUnknown() throws {
        var body = FactionFixture.relation(0x0100, modifier: -3, reaction: 0)
        body += FactionFixture.relation(0x0101, modifier: 7, reaction: 1)
        body += FactionFixture.relation(0x0102, modifier: 0, reaction: 2)
        body += FactionFixture.relation(0x0103, modifier: 1, reaction: 3)
        body += FactionFixture.relation(0x0104, modifier: 0, reaction: 9)
        let faction = try decode(body: body)

        #expect(faction.relations.map(\.faction) == [
            FormID(0x0100), FormID(0x0101), FormID(0x0102), FormID(0x0103), FormID(0x0104)
        ])
        #expect(faction.relations.map(\.modifier) == [-3, 7, 0, 1, 0])
        #expect(faction.relations.map(\.reaction) == [
            .neutral, .enemy, .ally, .friend, .unknown(raw: 9)
        ])
        #expect(faction.relations[4].reaction.description == "unknown (9)")
    }

    @Test
    func ranksRoundTripAndTitleLookupFallsBackToTheAuthoredGender() throws {
        var body = FactionFixture.rank(0, male: "Whelp")
        body += FactionFixture.rank(1, male: "Brother", female: "Sister")
        body += FactionFixture.rank(2, female: "Harbinger")
        let faction = try decode(body: body)

        #expect(faction.ranks.count == 3)
        #expect(faction.ranks.map(\.index) == [0, 1, 2])
        #expect(faction.rankTitle(1, female: false) == LString.inline("Brother"))
        #expect(faction.rankTitle(1, female: true) == LString.inline("Sister"))
        #expect(faction.rankTitle(0, female: true) == LString.inline("Whelp"))
        #expect(faction.rankTitle(2, female: false) == LString.inline("Harbinger"))
        #expect(faction.rankTitle(3, female: false) == nil)
    }

    @Test
    func crimeValuesDropTheirTailAtEveryDocumentedLength() throws {
        let full = try decode(body: FactionFixture.crimeValues())
        let values = try #require(full.crimeValues)
        #expect(values.arrest)
        #expect(!values.attackOnSight)
        #expect(values.murder == 1000)
        #expect(values.assault == 40)
        #expect(values.trespass == 5)
        #expect(values.pickpocket == 25)
        #expect(values.stealMultiplier == 0.5)
        #expect(values.escape == 100)
        #expect(values.werewolf == 1000)

        let short = try decode(body: FactionFixture.crimeValues(
            byteCount: Faction.CrimeValues.withStealMultiplierByteCount
        ))
        #expect(short.crimeValues?.stealMultiplier == 0.5)
        #expect(short.crimeValues?.escape == nil)
        #expect(short.crimeValues?.werewolf == nil)

        let shortest = try decode(body: FactionFixture.crimeValues(
            byteCount: Faction.CrimeValues.requiredByteCount
        ))
        #expect(shortest.crimeValues?.murder == 1000)
        #expect(shortest.crimeValues?.stealMultiplier == nil)
        #expect(shortest.skipped.total == 0)
    }

    @Test
    func vendorValuesTallyTheDisputedRadiusHighWord() throws {
        let plain = try decode(body: FactionFixture.vendorValues(radius: 1500))
        #expect(plain.vendorValues == Faction.VendorValues(
            startHour: 8,
            endHour: 18,
            radius: 1500,
            onlyBuysStolenItems: false,
            notSellBuy: false
        ))
        #expect(plain.skipped.vendorRadiusHighWordSet == 0)

        let disputed = try decode(body: FactionFixture.vendorValues(
            radius: 1,
            radiusHighWord: 1,
            onlyBuysStolenItems: true,
            notSellBuy: true
        ))
        #expect(disputed.skipped.vendorRadiusHighWordSet == 1)
        #expect(disputed.vendorValues?.radius == 1)
        #expect(disputed.vendorValues?.onlyBuysStolenItems == true)
        #expect(disputed.vendorValues?.notSellBuy == true)
    }

    @Test
    func truncatedAndUnknownFieldsAreTalliedRatherThanFatal() throws {
        var body = ESMFixture.field("CRVA", Data(count: 8))
        body += ESMFixture.field("VENV", Data(count: 4))
        body += ESMFixture.field("PLVD", Data(count: 4))
        body += ESMFixture.field("DATA", Data(count: 2))
        body += ESMFixture.field("MNAM", ESMFixture.zstring("NoRankYet"))
        body += ESMFixture.field("ZZZZ", Data(count: 4))
        body += FactionFixture.relation(0x0100, modifier: 0, reaction: 0)
        let faction = try decode(body: body)

        #expect(faction.crimeValues == nil)
        #expect(faction.vendorValues == nil)
        #expect(faction.vendorLocation == nil)
        #expect(faction.flags.isEmpty)
        #expect(faction.ranks.isEmpty)
        #expect(faction.skipped.malformedFields["CRVA"] == 1)
        #expect(faction.skipped.malformedFields["VENV"] == 1)
        #expect(faction.skipped.malformedFields["PLVD"] == 1)
        #expect(faction.skipped.malformedFields["DATA"] == 1)
        #expect(faction.skipped.unknownFields["MNAM"] == 1)
        #expect(faction.skipped.unknownFields["ZZZZ"] == 1)
        #expect(faction.relations.count == 1)
    }

    @Test
    func dropsAndTalliesAPartialRelationTail() throws {
        var relations = FactionFixture.relation(0x0100, modifier: 0, reaction: 0)
        // One whole entry plus five bytes of a second, written as one field.
        var payload = Data()
        payload.appendUInt32(0x0101)
        payload.appendUInt32(0)
        payload.appendUInt32(3)
        payload.append(Data(count: 5))
        relations += ESMFixture.field("XNAM", payload)
        let faction = try decode(body: relations)

        #expect(faction.relations.count == 2)
        #expect(faction.skipped.trailingBytes["XNAM"] == 5)
        #expect(faction.skipped.total == 5)
    }

    @Test
    func rejectsAnotherRecordType() throws {
        let bytes = ESMFixture.record(
            "LCTN",
            formID: 1,
            data: ESMFixture.field("EDID", ESMFixture.zstring("NotAFaction"))
        )
        let record = try FactionFixture.decode(bytes)
        #expect(throws: ESMError.self) {
            _ = try Faction(record: record, localized: false)
        }
    }

    @Test
    func recordDumpPrintsFlagsCrimeValuesRanksRelationsAndVendorBlock() throws {
        var body = FactionFixture.relation(0x0100, modifier: -3, reaction: 1)
        body += FactionFixture.flags(0x0000_4040)
        body += FactionFixture.link("JAIL", 0x0200)
        body += FactionFixture.crimeValues()
        body += FactionFixture.rank(0, male: "Whelp", female: "Whelp")
        body += FactionFixture.vendorValues()
        body += FactionFixture.vendorLocation(type: 12, value: 0, radius: 0)
        let record = try FactionFixture.decode(FactionFixture.record(
            formID: 0x10,
            editorID: "DumpFaction",
            name: "Dump Faction",
            body: body
        ))

        let dump = RecordTextDump.dump(record: record, localized: false)
        #expect(dump.contains("decoded FACT: editorID DumpFaction"))
        #expect(dump.contains("name \"Dump Faction\""))
        #expect(dump.contains("flags 0x00004040 [track crime, vendor]"))
        #expect(dump.contains("crime: arrest true, attack on sight false, murder 1000"))
        #expect(dump.contains("steal multiplier 0.5000, escape 100, werewolf 1000"))
        #expect(dump.contains("crime links: jail marker 00000200"))
        #expect(dump.contains("ranks (1):"))
        #expect(dump.contains("#0 male \"Whelp\", female \"Whelp\""))
        #expect(dump.contains("relations (1):"))
        #expect(dump.contains("00000100 enemy, modifier -3"))
        #expect(dump.contains("vendor: hours 8-18, radius 1500"))
        #expect(dump.contains("vendor location: type 12"))
    }

    @Test
    func recordDumpNamesAnUndocumentedFlagBit() throws {
        let record = try FactionFixture.decode(FactionFixture.record(
            formID: 0x11,
            editorID: "OddFlags",
            body: FactionFixture.flags(0x0080_0001)
        ))
        let dump = RecordTextDump.dump(record: record, localized: false)
        #expect(dump.contains("flags 0x00800001 [hidden from NPC, unknown 0x00800000]"))
    }

    private func decode(body: Data) throws -> Faction {
        try Faction(
            record: FactionFixture.decode(FactionFixture.record(
                formID: 0x10,
                editorID: "TestFaction",
                body: body
            )),
            localized: false
        )
    }
}
