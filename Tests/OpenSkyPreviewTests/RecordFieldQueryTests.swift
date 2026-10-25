// `record find`: decoded values as flat field paths, and the `--where` filters over them.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
@testable import OpenSkyPreview
import Testing

struct RecordFieldQueryTests {
    private struct Damage {
        let damage: UInt16
        let speed: Float
    }

    private struct Weapon {
        let editorID: String
        let keywords: [FormID]
        let data: Damage
        let enchantment: FormID?
    }

    private let weapon = Weapon(
        editorID: "IronDagger",
        keywords: [FormID(0x1E711), FormID(0x8F958)],
        data: Damage(damage: 4, speed: 1.3),
        enchantment: nil
    )

    private var fields: [RecordField] {
        RecordFields.flatten(weapon) { id in
            [FormID(0x1E711): "WeapTypeDagger", FormID(0x8F958): "VendorItemWeapon"][id]
                ?? id.description
        }
    }

    @Test func flattenNamesNestedFieldsAndSharesAListPath() {
        #expect(fields == [
            RecordField(path: "editorID", value: "IronDagger"),
            RecordField(path: "keywords", value: "WeapTypeDagger"),
            RecordField(path: "keywords", value: "VendorItemWeapon"),
            RecordField(path: "data.damage", value: "4"),
            RecordField(path: "data.speed", value: "1.3")
        ])
    }

    @Test func filtersReadTheirOperator() throws {
        let notEqual = try #require(RecordFieldFilter("editorID != Iron"))
        #expect(notEqual.path == "editorID" && notEqual.comparison?.operator == .notEqual)
        #expect(RecordFieldFilter("data.damage<=5")?.comparison?.operator == .lessOrEqual)
        #expect(RecordFieldFilter("enchantment")?.comparison == nil)
        #expect(RecordFieldFilter("=5") == nil)
        #expect(RecordFieldFilter("bad path=5") == nil)
    }

    @Test func aListMatchesWhenAnyElementDoes() throws {
        #expect(try #require(RecordFieldFilter("keywords=weaptypedagger")).matches(fields))
        #expect(try #require(RecordFieldFilter("keywords~Vendor")).matches(fields))
        #expect(try !#require(RecordFieldFilter("keywords!=WeapTypeDagger")).matches(fields))
        #expect(try #require(RecordFieldFilter("keywords!~Sword")).matches(fields))
    }

    @Test func numbersCompareAsNumbersAndAShortPathMatchesItsEnd() throws {
        #expect(try #require(RecordFieldFilter("damage>3")).matches(fields))
        #expect(try !#require(RecordFieldFilter("data.damage>=5")).matches(fields))
        #expect(try #require(RecordFieldFilter("speed<2")).matches(fields))
        #expect(try !#require(RecordFieldFilter("editorID>1")).matches(fields))
    }

    @Test func aBareFieldNeedsAValue() throws {
        #expect(try #require(RecordFieldFilter("editorID")).matches(fields))
        #expect(try !#require(RecordFieldFilter("enchantment")).matches(fields))
    }
}
