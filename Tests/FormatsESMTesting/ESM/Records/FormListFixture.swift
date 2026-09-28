// Synthetic FLST records, shared by the decoder tests and the form-list store
// tests. No game-derived bytes.

import Foundation
@testable import OpenSkyFormatsESM

public enum FormListFixture: Sendable {
    public static func record(
        formID: UInt32,
        editorID: String? = nil,
        entries: [UInt32] = []
    ) throws -> ESMRecord {
        try parse(recordBytes(formID: formID, editorID: editorID, entries: entries))
    }

    public static func recordBytes(
        formID: UInt32,
        editorID: String? = nil,
        entries: [UInt32] = []
    ) -> Data {
        var fields = Data()
        if let editorID {
            fields += ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        }
        for entry in entries {
            fields += ESMFixture.field("LNAM", uint32(entry))
        }
        return ESMFixture.record("FLST", formID: formID, data: fields)
    }

    public static func parse(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    public static func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
