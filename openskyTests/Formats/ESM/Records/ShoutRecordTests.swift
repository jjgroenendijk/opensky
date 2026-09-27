// Synthetic SHOU / WOOP / LVSP / DUAL / EQUP decoder coverage (issue #467).
// Every byte here is assembled in code from the published record layouts —
// never extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct ShoutRecordTests {
    // MARK: - SHOU

    @Test
    func decodesAShoutAndItsThreeWordEntries() throws {
        let record = try ShoutFixture.shout(
            editorID: "FireBreath",
            words: [
                ShoutFixture.WordSpec(word: 0x0A01, spell: 0x0B01, recovery: 20),
                ShoutFixture.WordSpec(word: 0x0A02, spell: 0x0B02, recovery: 45),
                ShoutFixture.WordSpec(word: 0x0A03, spell: 0x0B03, recovery: 100)
            ]
        )

        let shout = try Shout(record: record, localized: false)

        #expect(shout.editorID == "FireBreath")
        #expect(shout.name == .inline("Fire Breath"))
        #expect(shout.description == .inline("Your voice is fire."))
        #expect(shout.menuDisplayObject == FormID(0x0C01))
        #expect(shout.words.count == 3)
        #expect(shout.words.map(\.word) == [FormID(0x0A01), FormID(0x0A02), FormID(0x0A03)])
        #expect(shout.words.map(\.spell) == [FormID(0x0B01), FormID(0x0B02), FormID(0x0B03)])
        #expect(shout.words.map(\.recoveryTime) == [20, 45, 100])
        #expect(shout.skipped.total == 0)
    }

    /// The powers that are not really shouts store three all-zero entries
    /// rather than none, and those decode as present-but-unlinked.
    @Test
    func anAllZeroWordEntryDecodesAsAPlaceholderRatherThanALink() throws {
        let record = try ShoutFixture.shout(
            editorID: "WerewolfHowl",
            words: [ShoutFixture.WordSpec(word: 0, spell: 0, recovery: 0)]
        )

        let shout = try Shout(record: record, localized: false)

        #expect(shout.words.count == 1)
        #expect(shout.words[0].word == nil)
        #expect(shout.words[0].spell == nil)
        #expect(shout.words[0].recoveryTime == 0)
    }

    @Test
    func aTruncatedWordEntryIsTalliedWithoutLosingTheRecord() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Truncated"))
            + ESMFixture.field("SNAM", Data([1, 2, 3, 4]))
        let record = try ShoutFixture.record(type: "SHOU", fields: fields)

        let shout = try Shout(record: record, localized: false)

        #expect(shout.editorID == "Truncated")
        #expect(shout.words.isEmpty)
        #expect(shout.skipped.counts[.malformedField("SNAM")] == 1)
    }

    @Test
    func aShoutDecoderRejectsAnotherRecordType() throws {
        let record = try ShoutFixture.record(type: "WOOP", fields: Data())

        #expect(throws: ESMError.self) {
            _ = try Shout(record: record, localized: false)
        }
    }

    // MARK: - WOOP

    @Test
    func decodesAWordOfPowerAndItsTranslation() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("FireBreathWord1"))
            + ESMFixture.field("FULL", ESMFixture.zstring("Y3"))
            + ESMFixture.field("TNAM", ESMFixture.zstring("Yol"))
        let record = try ShoutFixture.record(type: "WOOP", fields: fields)

        let word = try WordOfPower(record: record, localized: false)

        #expect(word.editorID == "FireBreathWord1")
        #expect(word.name == .inline("Y3"))
        #expect(word.translation == .inline("Yol"))
        #expect(word.skipped.total == 0)
    }

    /// TNAM is present on every vanilla word but is often an empty string,
    /// which is data rather than a decode failure.
    @Test
    func anEmptyTranslationIsDataNotAFailure() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("MQFakeWord"))
            + ESMFixture.field("TNAM", ESMFixture.zstring(""))
        let record = try ShoutFixture.record(type: "WOOP", fields: fields)

        let word = try WordOfPower(record: record, localized: false)

        #expect(word.name == nil)
        #expect(word.translation == .inline(""))
        #expect(word.skipped.total == 0)
    }

    @Test
    func aWordDecoderRejectsAnotherRecordTypeAndTalliesUnknownFields() throws {
        let wrong = try ShoutFixture.record(type: "SHOU", fields: Data())
        #expect(throws: ESMError.self) {
            _ = try WordOfPower(record: wrong, localized: false)
        }

        let record = try ShoutFixture.record(
            type: "WOOP",
            fields: ESMFixture.field("ZZZZ", Data([1, 2]))
        )
        let word = try WordOfPower(record: record, localized: false)
        #expect(word.skipped.counts[.unknownField("ZZZZ")] == 1)
    }

    // MARK: - LVSP

    @Test
    func lvspDecodesThroughTheSharedLeveledListMachinery() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("LSpellFrost"))
        fields += ESMFixture.field("LVLD", Data([50]))
        fields += ESMFixture.field("LVLF", Data([0x03]))
        fields += ESMFixture.field("LLCT", Data([2]))
        fields += ESMFixture.field("LVLO", ShoutFixture.leveledEntry(level: 1, reference: 0x0B01))
        fields += ESMFixture.field("LVLO", ShoutFixture.leveledEntry(level: 25, reference: 0x0B02))
        let record = try ShoutFixture.record(type: "LVSP", fields: fields)

        let list = try LeveledList(record: record)

        #expect(list.recordType == "LVSP")
        #expect(list.editorID == "LSpellFrost")
        #expect(list.chanceNone == 50)
        #expect(list.flags.contains(.calculateFromAllLevels))
        #expect(list.flags.contains(.calculateForEach))
        #expect(list.entries.count == 2)
        #expect(list.entries.map(\.reference) == [FormID(0x0B01), FormID(0x0B02)])
        #expect(list.deterministicEntry?.level == 25)
    }

    @Test
    func theLeveledListDecoderStillRejectsUnrelatedRecordTypes() throws {
        let record = try ShoutFixture.record(type: "SHOU", fields: Data())

        #expect(throws: ESMError.self) {
            _ = try LeveledList(record: record)
        }
    }

    // MARK: - DUAL

    @Test
    func decodesDualCastArtAndItsInheritScaleFlags() throws {
        var data = Data()
        for link: UInt32 in [0x0201, 0x0202, 0, 0x0204, 0x0205] {
            data.appendUInt32(link)
        }
        data.appendUInt32(0x03)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("FrostStormDualCastData"))
            + ESMFixture.field("OBND", Data(repeating: 0, count: 12))
            + ESMFixture.field("DATA", data)
        let record = try ShoutFixture.record(type: "DUAL", fields: fields)

        let dual = try DualCastData(record: record)
        let art = try #require(dual.art)

        #expect(dual.editorID == "FrostStormDualCastData")
        #expect(dual.bounds?.isEmpty == true)
        #expect(art.projectile == FormID(0x0201))
        #expect(art.explosion == FormID(0x0202))
        #expect(art.effectShader == nil)
        #expect(art.hitEffectArt == FormID(0x0204))
        #expect(art.impactDataSet == FormID(0x0205))
        #expect(art.inheritScale == [.hitEffectArt, .projectile])
        #expect(dual.skipped.total == 0)
    }

    @Test
    func aTruncatedDualDataLeavesTheRecordWithoutArt() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Short"))
            + ESMFixture.field("DATA", Data(repeating: 0, count: 12))
        let record = try ShoutFixture.record(type: "DUAL", fields: fields)

        let dual = try DualCastData(record: record)

        #expect(dual.editorID == "Short")
        #expect(dual.art == nil)
        #expect(dual.skipped.counts[.malformedField("DATA")] == 1)
    }

    @Test
    func aDualDecoderRejectsAnotherRecordType() throws {
        let record = try ShoutFixture.record(type: "EQUP", fields: Data())

        #expect(throws: ESMError.self) {
            _ = try DualCastData(record: record)
        }
    }
}
