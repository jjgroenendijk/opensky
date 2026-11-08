// Field builders for the record detail tests. Synthetic bytes only; no game
// records are fixtures (AGENTS.md legal boundary).

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting

enum RecordDetailFixture {
    static func record(_ type: String, _ fields: Data) throws -> ESMRecord {
        try ESMFixture.parseRecord(ESMFixture.record(type, formID: 0x42, data: fields))
    }

    static func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }

    static func floats(_ values: Float...) -> Data {
        var data = Data()
        for value in values {
            data.appendFloat32(value)
        }
        return data
    }

    static func string(_ type: String, _ value: String) -> Data {
        ESMFixture.field(type, ESMFixture.zstring(value))
    }

    /// One FormID field per type, numbered from `first` in order.
    static func formIDs(_ types: [String], from first: UInt32) -> Data {
        types.enumerated().reduce(into: Data()) { data, entry in
            data += ESMFixture.field(entry.element, uint32(first + UInt32(entry.offset)))
        }
    }

    static func expectedIDs(_ count: Int, from first: UInt32) -> [FormID?] {
        (0 ..< count).map { FormID(first + UInt32($0)) }
    }

    /// OBND with corners (-1, -2, -3) and (4, 5, 6).
    static func boundsField() -> Data {
        var data = Data()
        for value: Int16 in [-1, -2, -3, 4, 5, 6] {
            data.appendUInt16(UInt16(bitPattern: value))
        }
        return ESMFixture.field("OBND", data)
    }

    static func isFixtureBounds(_ bounds: ObjectBounds?) -> Bool {
        bounds?.minimum == SIMD3(-1, -2, -3) && bounds?.maximum == SIMD3(4, 5, 6)
    }

    /// DEST with health 50 and one closed stage.
    static func destructibleFields() -> Data {
        var dest = Data()
        dest.appendUInt32(50)
        dest += Data([1, 0, 0, 0])
        var fields = ESMFixture.field("DEST", dest)
        fields += ESMFixture.field("DSTD", Data([50, 0, 1, 0]) + Data(count: 16))
        fields += ESMFixture.field("DSTF", Data())
        return fields
    }

    /// DODT with distinct values in each member.
    static func decalField() -> Data {
        var data = floats(1, 2, 3, 4, 5, 6, 7)
        data += Data([3, 0x05, 0, 0, 10, 20, 30, 0])
        return ESMFixture.field("DODT", data)
    }
}
