// Little-endian value builders for record fixtures, so a test spells a field
// payload as a list of values instead of hand-built byte arrays.

import Foundation
@testable import OpenSkyFormatsESM

extension ESMFixture {
    public static func u8(_ values: UInt8...) -> Data {
        Data(values)
    }

    public static func u16(_ values: UInt16...) -> Data {
        var data = Data()
        values.forEach { data.appendUInt16($0) }
        return data
    }

    public static func u32(_ values: UInt32...) -> Data {
        words(values)
    }

    public static func i32(_ values: Int32...) -> Data {
        words(values.map { UInt32(bitPattern: $0) })
    }

    public static func f32(_ values: Float...) -> Data {
        f32(values)
    }

    public static func f32(_ values: [Float]) -> Data {
        var data = Data()
        values.forEach { data.appendFloat32($0) }
        return data
    }

    /// A record of `type` from `(signature, payload)` pairs, parsed.
    public static func record(
        _ type: String,
        formID: UInt32 = 0x800,
        flags: UInt32 = 0,
        fields: [(String, Data)]
    ) throws -> ESMRecord {
        try parseRecord(recordBytes(type, formID: formID, flags: flags, fields: fields))
    }

    /// The unparsed bytes of `record(_:formID:flags:fields:)`, for a fixture plugin.
    public static func recordBytes(
        _ type: String,
        formID: UInt32 = 0x800,
        flags: UInt32 = 0,
        fields: [(String, Data)]
    ) -> Data {
        let bytes = fields.reduce(Data()) { $0 + field($1.0, $1.1) }
        return record(type, formID: formID, flags: flags, data: bytes)
    }
}
