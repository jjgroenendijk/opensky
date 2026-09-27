// Synthetic RELA and ASTP decode coverage: the whole DATA struct, the rank
// enum including a value the spec does not name, the two flag readings, the
// optional ASTP titles, and the defensive paths — wrong record type, truncated
// DATA, unknown field. No game-derived bytes.

import Foundation
@testable import opensky
import Testing

struct RelationshipTests {
    @Test
    func decodesTheWholeDataStruct() throws {
        let record = try RelationshipFixture.decode(RelationshipFixture.record(
            formID: 0x20,
            editorID: "RelaSpouse",
            body: RelationshipFixture.data(
                parent: 0x100,
                child: 0x101,
                rank: 0,
                unknown: 0,
                flags: 0x80,
                associationType: 0x300
            )
        ))
        let relationship = try Relationship(record: record)

        #expect(relationship.formID == FormID(0x20))
        #expect(relationship.editorID == "RelaSpouse")
        let data = try #require(relationship.data)
        #expect(data.parent == FormID(0x100))
        #expect(data.child == FormID(0x101))
        #expect(data.rank == .lover)
        #expect(data.unknown == 0)
        #expect(data.flags.contains(.secret))
        #expect(data.associationType == FormID(0x300))
        #expect(relationship.isSecret)
        #expect(!relationship.headerSecret)
        #expect(relationship.skipped.total == 0)
    }

    @Test
    func readsNullLinksAsAbsent() throws {
        let relationship = try decode(RelationshipFixture.record(
            formID: 0x21,
            editorID: "RelaHalfNamed",
            body: RelationshipFixture.data(parent: 0x100, child: 0, rank: 4)
        ))

        let data = try #require(relationship.data)
        #expect(data.parent == FormID(0x100))
        #expect(data.child == nil)
        #expect(data.associationType == nil)
        #expect(relationship.associationType == nil)
        #expect(!relationship.isSecret)
    }

    @Test
    func mapsEveryNamedRankToItsGetRelationshipRankValue() {
        // Raw value counts up from the friendliest, GetRelationshipRank counts
        // down from +4 — the list is in raw order, so the index is the raw
        // value and the signed value is 4 minus it.
        let named: [RelationshipRank] = [
            .lover, .ally, .confidant, .friend, .acquaintance,
            .rival, .foe, .enemy, .archnemesis
        ]
        for (raw, rank) in named.enumerated() {
            #expect(RelationshipRank(rawValue: UInt16(raw)) == rank)
            #expect(rank.rawValue == UInt16(raw))
            #expect(rank.signedRank == 4 - raw)
        }
    }

    @Test
    func keepsARankTheSpecDoesNotNameRatherThanClampingIt() throws {
        let relationship = try decode(RelationshipFixture.record(
            formID: 0x22,
            editorID: "RelaModded",
            body: RelationshipFixture.data(parent: 0x100, child: 0x101, rank: 42)
        ))

        #expect(relationship.rank == .unknown(raw: 42))
        #expect(relationship.rank?.rawValue == 42)
        #expect(relationship.rank?.signedRank == nil)
        #expect(relationship.rank?.description == "unknown (42)")
    }

    @Test
    func readsTheRecordHeaderSecretFlagSeparatelyFromTheDataFlag() throws {
        let relationship = try decode(RelationshipFixture.record(
            formID: 0x23,
            editorID: "RelaHeaderSecret",
            headerFlags: 0x40,
            body: RelationshipFixture.data(parent: 0x100, child: 0x101, rank: 1)
        ))

        #expect(relationship.headerSecret)
        #expect(!relationship.isSecret)
    }

    @Test
    func rejectsARecordOfTheWrongType() throws {
        let record = try RelationshipFixture.decode(RelationshipFixture.associationType(
            formID: 0x30,
            editorID: "AssocFamily"
        ))

        #expect(throws: ESMError.self) {
            try Relationship(record: record)
        }
        #expect(throws: ESMError.self) {
            try AssociationType(record: RelationshipFixture.decode(
                RelationshipFixture.record(formID: 0x20, editorID: "RelaSpouse")
            ))
        }
    }

    @Test
    func aTruncatedDataStructCostsItsOwnValueAndNotTheRecord() throws {
        let relationship = try decode(RelationshipFixture.record(
            formID: 0x24,
            editorID: "RelaShort",
            body: RelationshipFixture.data(
                parent: 0x100,
                child: 0x101,
                rank: 1,
                byteCount: 10
            )
        ))

        #expect(relationship.editorID == "RelaShort")
        #expect(relationship.data == nil)
        #expect(relationship.parent == nil)
        #expect(relationship.rank == nil)
        #expect(relationship.skipped.counts[.malformedField("DATA")] == 1)
    }

    @Test
    func anUnknownFieldIsTalliedRatherThanFatal() throws {
        let relationship = try decode(RelationshipFixture.record(
            formID: 0x25,
            editorID: "RelaExtra",
            body: RelationshipFixture.data(parent: 0x100, child: 0x101, rank: 3)
                + ESMFixture.field("ZZZZ", Data([1, 2, 3]))
        ))

        #expect(relationship.rank == .friend)
        #expect(relationship.skipped.counts[.unknownField("ZZZZ")] == 1)
    }

    @Test
    func decodesEveryAssociationTypeTitleAndTheFamilyFlag() throws {
        let record = try RelationshipFixture.decode(RelationshipFixture.associationType(
            formID: 0x30,
            editorID: "AssocParentChild",
            maleParent: "Father",
            femaleParent: "Mother",
            maleChild: "Son",
            femaleChild: "Daughter",
            flags: 0x0000_0001
        ))
        let type = try AssociationType(record: record)

        #expect(type.formID == FormID(0x30))
        #expect(type.editorID == "AssocParentChild")
        #expect(type.maleParentTitle == "Father")
        #expect(type.femaleParentTitle == "Mother")
        #expect(type.maleChildTitle == "Son")
        #expect(type.femaleChildTitle == "Daughter")
        #expect(type.isFamilyAssociation)
        #expect(type.parentTitle(female: true) == "Mother")
        #expect(type.childTitle(female: false) == "Son")
        #expect(type.skipped.total == 0)
    }

    @Test
    func anAssociationTypeThatNamesOneSideFallsBackToTheOther() throws {
        let record = try RelationshipFixture.decode(RelationshipFixture.associationType(
            formID: 0x31,
            editorID: "AssocAlly",
            maleParent: "Ally",
            extra: ESMFixture.field("ZZZZ", Data([0]))
        ))
        let type = try AssociationType(record: record)

        #expect(type.parentTitle(female: true) == "Ally")
        #expect(type.parentTitle(female: false) == "Ally")
        #expect(type.femaleParentTitle == nil)
        #expect(type.childTitle(female: false) == nil)
        #expect(!type.isFamilyAssociation)
        #expect(type.skipped.counts[.unknownField("ZZZZ")] == 1)
    }

    private func decode(_ bytes: Data) throws -> Relationship {
        try Relationship(record: RelationshipFixture.decode(bytes))
    }
}
