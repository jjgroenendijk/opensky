// The xEdit-named fields of list, sound, header, and package records that no
// game system reads yet, and the skip tally of every decoder that walks fields.
// Synthetic records only. Layout: docs/formats/records.md.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct ListSoundPackageDetailTests {
    private typealias Fixture = RecordDetailFixture

    /// Each decoder that tallies, with the fields it needs to decode at all.
    private struct TallyCase {
        let type: String
        var required = Data()
        let decode: @Sendable (ESMRecord) throws -> FieldTally
    }

    private static let tallyingDecoders: [TallyCase] = [
        TallyCase(type: "FLST", decode: { try FormList(record: $0).skipped }),
        TallyCase(type: "GLOB", decode: { try Global(record: $0).skipped }),
        TallyCase(type: "OTFT", decode: { try Outfit(record: $0).skipped }),
        TallyCase(type: "FSTP", decode: { try Footstep(record: $0).skipped }),
        TallyCase(type: "FSTS", decode: { try FootstepSet(record: $0).skipped }),
        TallyCase(type: "IPDS", decode: { try ImpactDataSet(record: $0).skipped }),
        TallyCase(type: "ALCH", decode: { try Ingestible(record: $0, localized: false).skipped }),
        TallyCase(type: "INGR", decode: { try Ingredient(record: $0, localized: false).skipped }),
        TallyCase(type: "LAND", decode: { try Land(record: $0).skipped }),
        TallyCase(type: "NAVI", decode: { try NavmeshInfoMap(record: $0).skipped }),
        TallyCase(type: "MUSC", decode: { try MusicType(record: $0).skipped }),
        TallyCase(type: "MUST", decode: { try MusicTrack(record: $0).skipped }),
        TallyCase(
            type: "SNCT",
            decode: { try SoundCategory(record: $0, localized: false).skipped }
        ),
        TallyCase(
            type: "LGTM",
            required: ESMFixture.field("DATA", Data(count: 40)),
            decode: { try LightingTemplate(record: $0).skipped }
        ),
        TallyCase(
            type: "GMST",
            required: Fixture.string("EDID", "fValue")
                + ESMFixture.field("DATA", Fixture.floats(1)),
            decode: { try GameSetting(record: $0, localized: false).skipped }
        )
    ]

    @Test func everyTallyingDecoderCountsAnUnknownField() throws {
        for entry in Self.tallyingDecoders {
            let fields = entry.required + ESMFixture.field("XYZW", Data(count: 2))
            let skipped = try entry.decode(Fixture.record(entry.type, fields))
            #expect(skipped.counts == [.unknownField("XYZW"): 1], "\(entry.type)")
        }
    }

    @Test func leveledListReadsOwnerConditionBoundsAndModel() throws {
        var entry = Data()
        entry.appendUInt16(1)
        entry.appendUInt16(0)
        entry.appendUInt32(0x20)
        entry.appendUInt32(1)
        var coed = Fixture.uint32(0x30)
        coed.appendUInt32(7)
        coed.appendFloat32(1)
        var fields = Fixture.boundsField()
        fields += Fixture.string("MODL", "list.nif")
        fields += ESMFixture.field("LVLO", entry)
        fields += ESMFixture.field("COED", coed)
        let list = try LeveledList(record: Fixture.record("LVLN", fields))
        #expect(list.skipped.isEmpty)
        #expect(Fixture.isFixtureBounds(list.bounds))
        #expect(list.model?.path == "list.nif")
        #expect(list.entries.first?.ownerCondition == 7)
    }

    @Test func pluginHeaderKeepsScreenshotAndINTV() throws {
        var hedr = Fixture.floats(1.71)
        hedr.appendUInt32(0)
        hedr.appendUInt32(0x800)
        var fields = ESMFixture.field("HEDR", hedr)
        fields += ESMFixture.field("SCRN", Data([1, 2]))
        fields += ESMFixture.field("INTV", Fixture.uint32(9))
        let header = try PluginHeader(tes4: Fixture.record("TES4", fields))
        #expect(header.skipped.isEmpty)
        #expect(header.screenshot == Data([1, 2]))
        #expect(header.intv == Fixture.uint32(9))
    }

    @Test func armorAddonReadsEverySkinSlot() throws {
        let fields = Fixture.formIDs(["NAM0", "NAM1", "NAM2", "NAM3"], from: 0x10)
        let addon = try ArmorAddon(record: Fixture.record("ARMA", fields))
        #expect([
            addon.maleSkinTexture,
            addon.femaleSkinTexture,
            addon.maleSkinTextureSwapList,
            addon.femaleSkinTextureSwapList
        ] == Fixture.expectedIDs(4, from: 0x10))
    }

    @Test func soundRecordsKeepConditionsAndLegacyFields() throws {
        var ctda = Data(count: 32)
        ctda[8] = 35
        var sndr = ESMFixture.field("CTDA", ctda)
        sndr += ESMFixture.field("FNAM", Fixture.uint32(0x10))
        let descriptor = try SoundDescriptor(record: Fixture.record("SNDR", sndr))
        #expect(descriptor.skipped.isEmpty)
        #expect(descriptor.conditions.map(\.functionIndex) == [35])
        #expect(descriptor.legacyFlags == 0x10)
        var soun = Fixture.boundsField()
        soun += ESMFixture.field("FNAM", Data([1]))
        soun += ESMFixture.field("SNDD", Data([2]))
        let marker = try SoundMarker(record: Fixture.record("SOUN", soun))
        #expect(marker.skipped.isEmpty)
        #expect(Fixture.isFixtureBounds(marker.bounds))
        #expect(marker.legacyFNAM == Data([1]))
        #expect(marker.legacySNDD == Data([2]))
    }

    @Test func packageReadsIdlesBranchesInputsAndEvents() throws {
        var pfo2 = Fixture.uint32(1) + Fixture.uint32(2)
        pfo2.appendUInt16(3)
        pfo2.appendUInt16(4)
        pfo2 += Data([2, 0, 0, 0])
        var ctda = Data(count: 32)
        ctda[8] = 35
        var fields = ESMFixture.field("PKDT", Data([0, 0, 0, 0, 19]) + Data(count: 7))
        fields += ESMFixture.field("PSDT", Data(count: 12))
        fields += ESMFixture.field("IDLF", Data([1]))
        fields += ESMFixture.field("IDLC", Data([1]))
        fields += ESMFixture.field("IDLT", Fixture.floats(4))
        fields += ESMFixture.field("CNAM", Fixture.uint32(0x50))
        fields += ESMFixture.field("PKCU", Data(count: 12))
        fields += ESMFixture.field("XNAM", Data([0]))
        fields += Fixture.string("ANAM", "Procedure")
        fields += ESMFixture.field("CTDA", ctda)
        fields += ESMFixture.field("PRCB", Fixture.uint32(0) + Fixture.uint32(1))
        fields += ESMFixture.field("PFO2", pfo2)
        fields += ESMFixture.field("UNAM", Data([0xFF]))
        fields += ESMFixture.field("POBA", Data())
        fields += ESMFixture.field("INAM", Fixture.uint32(0x60))
        let package = try Package(record: Fixture.record("PACK", fields))
        let details = package.details
        #expect(package.skipped.isEmpty)
        #expect(details.idleAnimations?.flags == 1)
        #expect(details.idleAnimations?.declaredCount == 1)
        #expect(details.idleAnimations?.timer == 4)
        #expect(details.combatStyle == FormID(0x50))
        let branch = try #require(details.branches.first)
        #expect(branch.type == "Procedure")
        #expect(branch.conditions.map(\.functionIndex) == [35])
        #expect(branch.rootFlags == 1)
        let override = try #require(branch.flagsOverrides.first)
        #expect([override.setGeneralFlags, override.clearGeneralFlags] == [1, 2])
        #expect([override.setInterruptFlags, override.clearInterruptFlags] == [3, 4])
        #expect(override.preferredSpeed == 2)
        #expect(details.templateInputs.map(\.index) == [-1])
        #expect(details.onBegin?.idle == FormID(0x60))
    }
}
