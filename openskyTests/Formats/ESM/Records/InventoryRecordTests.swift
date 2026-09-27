// Shared inventory-subrecord helpers (OBND, KSIZ/KWDA, the value+weight DATA)
// and the two simplest carryable families, MISC and BOOK. Fixtures are
// synthetic in-code records (InventoryFixture) — never extracted game files
// (AGENTS.md "Legal & IP boundary").
//
// Layouts: UESP "Skyrim Mod:Mod File Format" subpages /MISC and /BOOK,
// cross-checked against xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas.
// See docs/formats/records.md.

import Foundation
@testable import opensky
import Testing

struct InventorySubrecordTests {
    @Test func objectBoundsDecodesSignedCorners() throws {
        var data = Data()
        for value: Int16 in [-4, -8, 0, 4, 8, 16] {
            data.appendUInt16(UInt16(bitPattern: value))
        }
        let bounds = try ObjectBounds(field: ESMField(type: "OBND", data: data))
        #expect(bounds.minimum == SIMD3<Int16>(-4, -8, 0))
        #expect(bounds.maximum == SIMD3<Int16>(4, 8, 16))
        #expect(!bounds.isEmpty)
    }

    @Test func objectBoundsAllZeroIsEmpty() throws {
        let bounds = try ObjectBounds(field: ESMField(type: "OBND", data: Data(count: 12)))
        #expect(bounds.isEmpty)
    }

    @Test func objectBoundsRejectsTruncatedField() {
        #expect(throws: ESMError.self) {
            _ = try ObjectBounds(field: ESMField(type: "OBND", data: Data(count: 11)))
        }
    }

    /// KSIZ is advisory: the payload length decides how many keywords exist,
    /// so a stale count neither truncates the list nor overruns the field.
    @Test func keywordListReadsPayloadLengthNotKSIZ() throws {
        var list = KeywordList()
        var count = Data()
        count.appendUInt32(9) // deliberately wrong
        var payload = Data()
        payload.appendUInt32(0x1234)
        payload.appendUInt32(0x5678)
        #expect(try list.decode(field: ESMField(type: "KSIZ", data: count)))
        #expect(try list.decode(field: ESMField(type: "KWDA", data: payload)))
        #expect(list.keywords == [FormID(0x1234), FormID(0x5678)])
        #expect(list.declaredCount == 9)
        #expect(list.countMismatch)
        #expect(list.contains(FormID(0x5678)))
        #expect(try !list.decode(field: ESMField(type: "EDID", data: Data())))
    }

    @Test func keywordListIgnoresTrailingPartialFormID() throws {
        var list = KeywordList()
        var payload = Data()
        payload.appendUInt32(0x11)
        payload.append(contentsOf: [0xFF, 0xFF]) // half a FormID
        #expect(try list.decode(field: ESMField(type: "KWDA", data: payload)))
        #expect(list.keywords == [FormID(0x11)])
    }

    @Test func itemValueRejectsTruncatedData() {
        #expect(throws: ESMError.self) {
            _ = try ItemValue(field: ESMField(type: "DATA", data: Data(count: 7)))
        }
    }
}

struct MiscItemRecordTests {
    @Test func decodesMiscellaneousItem() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("Gold001"))
        fields += ESMFixture.field("OBND", InventoryFixture.boundsData())
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Gold"))
        fields += ESMFixture.field("MODL", ESMFixture.zstring("clutter\\coin01.nif"))
        fields += ESMFixture.field("ICON", ESMFixture.zstring("interface\\icons\\gold.dds"))
        fields += InventoryFixture.formIDField("YNAM", 0x0003_C7BC)
        fields += InventoryFixture.formIDField("ZNAM", 0x0003_C7BD)
        fields += InventoryFixture.keywordFields([0x0008_5FF9])
        fields += ESMFixture.field(
            "DATA", InventoryFixture.valueWeightData(value: 1, weight: 0)
        )
        let item = try MiscItem(
            record: InventoryFixture.record(
                ESMFixture.record("MISC", formID: 0x0F, data: fields)
            ),
            localized: false
        )
        #expect(item.formID == FormID(0x0F))
        #expect(item.fields.editorID == "Gold001")
        #expect(item.fields.name == .inline("Gold"))
        #expect(item.fields.modelPath == "clutter\\coin01.nif")
        #expect(item.fields.iconPath == "interface\\icons\\gold.dds")
        #expect(item.fields.pickupSound == FormID(0x0003_C7BC))
        #expect(item.fields.dropSound == FormID(0x0003_C7BD))
        #expect(item.fields.keywords.keywords == [FormID(0x0008_5FF9)])
        #expect(item.fields.bounds?.maximum == SIMD3<Int16>(2, 2, 2))
        #expect(item.itemValue == ItemValue(value: 1, weight: 0))
    }

    @Test func rejectsWrongRecordType() {
        #expect(throws: ESMError.self) {
            _ = try MiscItem(
                record: InventoryFixture.record(ESMFixture.record("BOOK", data: Data())),
                localized: false
            )
        }
    }

    @Test func emptyRecordDecodesToDefaults() throws {
        let item = try MiscItem(
            record: InventoryFixture.record(
                ESMFixture.record("MISC", formID: 7, data: Data())
            ),
            localized: false
        )
        #expect(item.formID == FormID(7))
        #expect(item.fields.editorID == nil)
        #expect(item.fields.bounds == nil)
        #expect(item.itemValue == .zero)
    }

    @Test func rejectsTruncatedData() {
        let fields = ESMFixture.field("DATA", Data(count: 4))
        #expect(throws: ESMError.self) {
            _ = try MiscItem(
                record: InventoryFixture.record(ESMFixture.record("MISC", data: fields)),
                localized: false
            )
        }
    }
}

struct BookRecordTests {
    @Test func decodesSkillBook() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("SkillBook"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("The Book"))
        fields += ESMFixture.field("DESC", ESMFixture.zstring("Body text."))
        fields += ESMFixture.field("CNAM", ESMFixture.zstring("Blurb."))
        fields += ESMFixture.field(
            "DATA",
            InventoryFixture.bookData(
                flags: 0x01, kind: 0, teaches: 0x12, value: 50, weight: 1
            )
        )
        let book = try Book(
            record: InventoryFixture.record(
                ESMFixture.record("BOOK", formID: 0x21, data: fields)
            ),
            localized: false
        )
        #expect(book.flags == [.teachesSkill])
        #expect(book.kind == .book)
        #expect(book.teaches == .skill(0x12))
        #expect(book.text == .inline("Body text."))
        #expect(book.inventoryDescription == .inline("Blurb."))
        #expect(book.itemValue == ItemValue(value: 50, weight: 1))
    }

    /// The teaches word is a union: the same four bytes are a SPEL FormID when
    /// flag 0x04 is set, and 0x04 wins over 0x01 if a mod sets both.
    @Test func spellTomeDecodesTeachesAsFormID() throws {
        let fields = ESMFixture.field(
            "DATA",
            InventoryFixture.bookData(
                flags: 0x05, kind: 255, teaches: 0x0001_0001, value: 0, weight: 0
            )
        )
        let book = try Book(
            record: InventoryFixture.record(ESMFixture.record("BOOK", data: fields)),
            localized: false
        )
        #expect(book.teaches == .spell(FormID(0x0001_0001)))
        #expect(book.kind == .note)
    }

    @Test func noTeachFlagIgnoresTheUnionWord() throws {
        let fields = ESMFixture.field(
            "DATA",
            InventoryFixture.bookData(
                flags: 0x02, kind: 0, teaches: 0xDEAD_BEEF, value: 0, weight: 0
            )
        )
        let book = try Book(
            record: InventoryFixture.record(ESMFixture.record("BOOK", data: fields)),
            localized: false
        )
        #expect(book.teaches == .nothing)
        #expect(book.flags == [.cannotBeTaken])
    }

    @Test func rejectsWrongTypeAndTruncatedData() {
        #expect(throws: ESMError.self) {
            _ = try Book(
                record: InventoryFixture.record(ESMFixture.record("MISC", data: Data())),
                localized: false
            )
        }
        #expect(throws: ESMError.self) {
            _ = try Book(
                record: InventoryFixture.record(
                    ESMFixture.record("BOOK", data: ESMFixture.field("DATA", Data(count: 15)))
                ),
                localized: false
            )
        }
    }

    @Test func emptyRecordDecodesToDefaults() throws {
        let book = try Book(
            record: InventoryFixture.record(ESMFixture.record("BOOK", data: Data())),
            localized: false
        )
        #expect(book.teaches == .nothing)
        #expect(book.text == nil)
        #expect(book.itemValue == .zero)
    }
}
