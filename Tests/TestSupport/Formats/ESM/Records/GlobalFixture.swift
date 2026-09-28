// Synthetic GLOB record bytes shared by the global-variable tests. Built in
// code, never extracted from game data (AGENTS.md "Legal & IP boundary").
// Layout: UESP "Skyrim Mod:Mod File Format/GLOB".

import Foundation
@testable import opensky

enum GlobalFixture {
    /// GLOB record: EDID zstring, FNAM type character, FLTV float32.
    static func record(
        formID: UInt32,
        editorID: String?,
        type: Global.ValueType,
        value: Float,
        isConstant: Bool = false
    ) -> Data {
        var fields = Data()
        if let editorID {
            fields += ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        }
        fields += ESMFixture.field("FNAM", Data([type.fnam]))
        var fltv = Data()
        fltv.appendUInt32(value.bitPattern)
        fields += ESMFixture.field("FLTV", fltv)
        return ESMFixture.record(
            "GLOB",
            formID: formID,
            flags: isConstant ? 0x40 : 0,
            data: fields
        )
    }

    /// Plugin carrying a TES4 header and one GLOB top group.
    static func plugin(_ records: Data) -> Data {
        ESMFixture.tes4() + ESMFixture.topGroup("GLOB", contents: records)
    }

    /// First record parsed out of raw fixture bytes.
    static func parse(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    /// Store over `records` with no masters, so every GLOB resolves to
    /// `ReferenceKey.plugin(name: "test.esm", objectID:)`.
    static func store(_ records: Data) throws -> GlobalStore {
        try GlobalStore(file: ESMFile(data: plugin(records)), pluginName: "Test.esm")
    }

    /// The key a fixture FormID resolves to under `store(_:)`.
    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "test.esm", objectID: objectID)
    }
}
