// The ring keeps a listed large reference only while its static is still large by
// `fLargeRefMinSize`. Synthetic records only.

import Foundation
@testable import OpenSkyCells
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct LargeReferenceSizeTests {
    private static func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }

    /// A static whose bounds are a cube `width` units wide.
    private static func stat(_ formID: UInt32, width: Int16) throws -> StaticObject {
        var bounds = Data()
        for value in [-width / 2, -width / 2, -width / 2, width / 2, width / 2, width / 2] {
            bounds.appendUInt16(UInt16(bitPattern: value))
        }
        return try StaticObject(record: ESMFixture.parseRecord(ESMFixture.record(
            "STAT", formID: formID, data: ESMFixture.field("OBND", bounds)
        )))
    }

    private static func reference(_ formID: UInt32, base: UInt32) throws -> CollectedReference {
        let record = try PlacedReference(record: ESMFixture.parseRecord(ESMFixture.record(
            "REFR",
            formID: formID,
            data: ESMFixture.field("NAME", uint32(base)) + ESMFixture.field("DATA", Data(count: 24))
        )))
        return CollectedReference(reference: record, isPersistent: false)
    }

    @Test func aListedStaticBelowTheMinimumIsDropped() throws {
        let statics: [UInt32: StaticObject] = try [
            0x10: Self.stat(0x10, width: 1200), 0x11: Self.stat(0x11, width: 400)
        ]
        let collected = try [
            Self.reference(0x100, base: 0x10),
            Self.reference(0x101, base: 0x11),
            Self.reference(0x102, base: 0x10),
            Self.reference(0x103, base: 0x99)
        ]
        let kept = LargeReferenceFilter(statics: statics, settings: .vanilla)
            .kept([0x100, 0x101, 0x103], of: collected)
        #expect(kept == [0x100, 0x103])
    }
}
