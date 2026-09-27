// Synthetic LCTN/LCRT layout coverage. No game-derived bytes.

import Foundation
@testable import opensky
import Testing

struct LocationTests {
    @Test
    func decodesLocationIdentityLinksAndEveryPackedArrayFamily() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("TestLocation"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Test Place"))
        fields += wordField("PNAM", 0x10) + wordField("KSIZ", 2)
        fields += ESMFixture.field("KWDA", words([0x20, 0x21]))
        fields += ESMFixture.field("ACPR", persistent(1, 2, -3, 4))
        fields += ESMFixture.field("LCPR", persistent(5, 6, 7, -8))
        fields += ESMFixture.field("RCPR", words([9, 10]))
        fields += ESMFixture.field("ACUN", words([11, 12, 13]))
        fields += ESMFixture.field("LCUN", words([14, 15, 16]))
        fields += ESMFixture.field("RCUN", words([17]))
        fields += ESMFixture.field("ACSR", special(18, 19, 20, -21, 22))
        fields += ESMFixture.field("LCSR", special(23, 24, 25, 26, -27))
        fields += ESMFixture.field("RCSR", words([28]))
        fields += ESMFixture.field("ACEC", worldCells(29, [(30, 31)]))
        fields += ESMFixture.field("LCEC", worldCells(32, [(33, 34), (35, 36)]))
        fields += ESMFixture.field("RCEC", worldCells(37, []))
        fields += ESMFixture.field("ACID", words([38]))
        fields += ESMFixture.field("LCID", words([39, 40]))
        fields += ESMFixture.field("ACEP", enableParent(41, 42, 1))
        fields += ESMFixture.field("LCEP", enableParent(43, 44, 2))
        let location = try Location(record: record("LCTN", fields), localized: false)

        #expect(location.editorID == "TestLocation")
        #expect(location.name == LString.inline("Test Place"))
        #expect(location.parent == FormID(0x10))
        #expect(location.keywords.keywords == [FormID(0x20), FormID(0x21)])
        #expect(location.addedPersistentReferences.first?.gridY == -3)
        #expect(location.persistentReferences.first?.gridX == -8)
        #expect(location.removedPersistentReferences == [FormID(9), FormID(10)])
        #expect(location.addedUniqueActors.first?.actorReference == FormID(12))
        #expect(location.uniqueActors.first?.location == FormID(16))
        #expect(location.removedUniqueActors == [FormID(17)])
        #expect(location.addedSpecialReferences.first?.type == FormID(18))
        #expect(location.specialReferences.first?.gridX == -27)
        #expect(location.removedSpecialReferences == [FormID(28)])
        #expect(location.addedWorldspaceCells.first?.cells.first?.y == 30)
        #expect(location.worldspaceCells.first?.cells.count == 2)
        #expect(location.removedWorldspaceCells.first?.worldspace == FormID(37))
        #expect(location.addedInitiallyDisabledReferences == [FormID(38)])
        #expect(location.initiallyDisabledReferences == [FormID(39), FormID(40)])
        #expect(location.addedEnableParents.first?.parent == FormID(42))
        #expect(location.enableParents.first?.flags == 2)
        #expect(location.skipped.trailingArrayBytes.isEmpty)
    }

    @Test
    func dropsAndTalliesEveryPartialArrayTail() throws {
        let fields = ESMFixture.field("ACPR", persistent(1, 2, 3, 4) + Data([0xAA]))
            + ESMFixture.field("ACUN", words([5, 6, 7]) + Data([0xBB, 0xCC]))
            + ESMFixture.field("ACSR", special(8, 9, 10, 11, 12) + Data([0xDD]))
            + ESMFixture.field("RCPR", words([13]) + Data([1, 2, 3]))
            + ESMFixture.field("ACEC", worldCells(14, [(15, 16)]) + Data([1, 2]))
            + ESMFixture.field("ACEP", enableParent(17, 18, 0) + Data([1]))
        let location = try Location(record: record("LCTN", fields), localized: false)

        #expect(location.addedPersistentReferences.count == 1)
        #expect(location.addedUniqueActors.count == 1)
        #expect(location.addedSpecialReferences.count == 1)
        #expect(location.removedPersistentReferences == [FormID(13)])
        #expect(location.addedWorldspaceCells.first?.cells.count == 1)
        #expect(location.addedEnableParents.count == 1)
        #expect(location.skipped.trailingArrayBytes["ACPR"] == 1)
        #expect(location.skipped.trailingArrayBytes["ACUN"] == 2)
        #expect(location.skipped.trailingArrayBytes["ACSR"] == 1)
        #expect(location.skipped.trailingArrayBytes["RCPR"] == 3)
        #expect(location.skipped.trailingArrayBytes["ACEC"] == 2)
        #expect(location.skipped.trailingArrayBytes["ACEP"] == 1)
    }

    @Test
    func decodesLocationReferenceTypeAndTalliesMalformedFields() throws {
        let valid = try LocationRefType(record: record(
            "LCRT",
            ESMFixture.field("EDID", ESMFixture.zstring("BossContainer"))
                + ESMFixture.field("CNAM", Data([1, 2, 3, 4]))
        ))
        let malformed = try LocationRefType(record: record(
            "LCRT",
            ESMFixture.field("CNAM", Data([1, 2, 3]))
        ))
        let dumpRecord = try record(
            "LCRT",
            ESMFixture.field("EDID", ESMFixture.zstring("BossContainer"))
        )

        #expect(valid.editorID == "BossContainer")
        #expect(valid.editorColor?.blue == 3)
        #expect(RecordTextDump.dump(record: dumpRecord, localized: false)
            .contains("decoded LCRT: editorID BossContainer"))
        #expect(malformed.skipped.counts[.malformedField("CNAM")] == 1)
    }

    private func record(_ type: String, _ fields: Data) throws -> ESMRecord {
        let bytes = ESMFixture.record(type, formID: 0x100, data: fields)
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("location fixture did not produce a record")
        }
        return record
    }

    private func wordField(_ type: String, _ value: UInt32) -> Data {
        ESMFixture.field(type, words([value]))
    }

    private func words(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            data.appendUInt32(value)
        }
        return data
    }

    private func persistent(_ ref: UInt32, _ cell: UInt32, _ y: Int16, _ x: Int16) -> Data {
        words([ref, cell]) + signedWords([y, x])
    }

    private func special(
        _ type: UInt32,
        _ ref: UInt32,
        _ cell: UInt32,
        _ y: Int16,
        _ x: Int16
    ) -> Data {
        words([type, ref, cell]) + signedWords([y, x])
    }

    private func worldCells(_ world: UInt32, _ cells: [(Int16, Int16)]) -> Data {
        words([world]) + signedWords(cells.flatMap { [$0.0, $0.1] })
    }

    private func enableParent(_ ref: UInt32, _ parent: UInt32, _ flags: UInt8) -> Data {
        words([ref, parent]) + Data([flags, 0, 0, 0])
    }

    private func signedWords(_ values: [Int16]) -> Data {
        var data = Data()
        for value in values {
            data.appendUInt16(UInt16(bitPattern: value))
        }
        return data
    }
}
