// FSTP / FSTS / IPDS / IPCT decoding over synthetic ESM fields only. Layout
// sources: UESP FSTP/FSTS/IPDS/IPCT and xEdit wbDefinitionsTES5.pas; see
// docs/formats/footstep.md.

import Foundation
@testable import opensky
import Testing

struct FootstepRecordTests {
    @Test func decodesFootstep() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("DefaultFootWalkLFootstep"))
            + ESMFixture.field("DATA", uint32(0x12F0B))
            + ESMFixture.field("ANAM", ESMFixture.zstring("FootLeft"))
        let footstep = try Footstep(
            record: record(ESMFixture.record("FSTP", formID: 0x12F0F, data: fields))
        )

        #expect(footstep.formID == FormID(0x12F0F))
        #expect(footstep.editorID == "DefaultFootWalkLFootstep")
        #expect(footstep.impactDataSet == FormID(0x12F0B))
        #expect(footstep.tag == "FootLeft")
    }

    @Test func nullAndWrongSizeImpactLinksDecodeAsAbsent() throws {
        let fields = ESMFixture.field("DATA", uint32(0))
        let nulled = try Footstep(record: record(ESMFixture.record("FSTP", data: fields)))
        #expect(nulled.impactDataSet == nil)

        let short = try Footstep(
            record: record(
                ESMFixture.record("FSTP", data: ESMFixture.field("DATA", Data(count: 2)))
            )
        )
        #expect(short.impactDataSet == nil)
    }

    @Test func wrongRecordTypeThrows() {
        #expect(throws: ESMError.self) {
            _ = try Footstep(record: record(ESMFixture.record("FSTS", data: Data())))
        }
        #expect(throws: ESMError.self) {
            _ = try FootstepSet(record: record(ESMFixture.record("FSTP", data: Data())))
        }
    }

    /// XCNT lists its counts walk-first while the DATA array they size is laid
    /// out swim-first (xEdit `wbRecord(FSTS, ...)`). Distinct counts per gait
    /// are what make the two orders distinguishable, so the fixture uses five
    /// different ones.
    @Test func splitsDataArraySwimFirstAgainstWalkFirstCounts() throws {
        let set = try footstepSet(
            counts: [4, 3, 2, 1, 5],
            footsteps: Array(1 ... 15).map { UInt32($0) }
        )

        #expect(set.footsteps(for: .swimming).map(\.rawValue) == [1, 2, 3, 4, 5])
        #expect(set.footsteps(for: .sneaking).map(\.rawValue) == [6])
        #expect(set.footsteps(for: .sprinting).map(\.rawValue) == [7, 8])
        #expect(set.footsteps(for: .running).map(\.rawValue) == [9, 10, 11])
        #expect(set.footsteps(for: .walking).map(\.rawValue) == [12, 13, 14, 15])
    }

    @Test func countsThatOverrunTheArrayTruncateInsteadOfThrowing() throws {
        let set = try footstepSet(counts: [4, 4, 4, 4, 4], footsteps: [1, 2, 3, 4, 5, 6])

        #expect(set.footsteps(for: .swimming).map(\.rawValue) == [1, 2, 3, 4])
        #expect(set.footsteps(for: .sneaking).map(\.rawValue) == [5, 6])
        #expect(set.footsteps(for: .sprinting).isEmpty)
        #expect(set.footsteps(for: .walking).isEmpty)
    }

    @Test func wrongSizeCountStructLeavesEveryListEmpty() throws {
        let fields = ESMFixture.field("XCNT", Data(count: 16))
            + ESMFixture.field("DATA", uint32(1) + uint32(2))
        let set = try FootstepSet(record: record(ESMFixture.record("FSTS", data: fields)))

        for gait in FootstepGait.allCases {
            #expect(set.footsteps(for: gait).isEmpty)
        }
    }

    @Test func decodesImpactSoundLinks() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("FSTStoneWalkLImpact"))
            + ESMFixture.field("SNAM", uint32(0x300))
            + ESMFixture.field("NAM1", uint32(0x301))
        let impact = try Impact(
            record: record(ESMFixture.record("IPCT", formID: 0x200, data: fields))
        )

        #expect(impact.formID == FormID(0x200))
        #expect(impact.editorID == "FSTStoneWalkLImpact")
        #expect(impact.sound == FormID(0x300))
        #expect(impact.secondarySound == FormID(0x301))
    }

    @Test func impactDataSetPairsMaterialsWithImpacts() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("StoneSet"))
            + ESMFixture.field("PNAM", uint32(0x10) + uint32(0x100))
            + ESMFixture.field("PNAM", uint32(0x11) + uint32(0x101))
            + ESMFixture.field("PNAM", uint32(0x12) + uint32(0x101))
            + ESMFixture.field("PNAM", uint32(0x13) + uint32(0)) // null impact, dropped
            + ESMFixture.field("PNAM", Data(count: 4)) // short pair, dropped
        let set = try ImpactDataSet(
            record: record(ESMFixture.record("IPDS", formID: 0x400, data: fields))
        )

        #expect(set.entries.count == 3)
        #expect(set.impact(for: FormID(0x10)) == FormID(0x100))
        // The representative impact is the most frequently paired one, which is
        // what a caller with no surface material under the foot gets.
        #expect(set.impact(for: nil) == FormID(0x101))
        // A material the table does not list falls back the same way.
        #expect(set.impact(for: FormID(0xFF)) == FormID(0x101))
        #expect(ImpactDataSet(formID: FormID(1), editorID: nil, entries: [])
            .impact(for: nil) == nil)
    }

    @Test func armorAddonCarriesItsFootstepSet() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("NakedFeet"))
            + ESMFixture.field("SNDD", uint32(0x21468))
        let addon = try ArmorAddon(
            record: record(ESMFixture.record("ARMA", formID: 0x500, data: fields))
        )

        #expect(addon.footstepSound == FormID(0x21468))

        let nulled = try ArmorAddon(
            record: record(
                ESMFixture.record("ARMA", data: ESMFixture.field("SNDD", uint32(0)))
            )
        )
        #expect(nulled.footstepSound == nil)
    }

    // MARK: - Helpers

    private func footstepSet(counts: [UInt32], footsteps: [UInt32]) throws -> FootstepSet {
        var countData = Data()
        for count in counts {
            countData.appendUInt32(count)
        }
        var listData = Data()
        for id in footsteps {
            listData.appendUInt32(id)
        }
        let fields = ESMFixture.field("XCNT", countData)
            + ESMFixture.field("DATA", listData)
        return try FootstepSet(record: record(ESMFixture.record("FSTS", data: fields)))
    }

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    private func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
