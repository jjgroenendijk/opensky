// Synthetic RELA and ASTP records for the relationship decoder and store
// suites. Every layout is authored from the cited field spec
// (docs/formats/relationships.md) and contains no bytes from the game install
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky

enum RelationshipFixture {
    /// The 16-byte DATA struct, optionally truncated to stand in for a record
    /// a mod wrote short.
    static func data(
        parent: UInt32,
        child: UInt32,
        rank: UInt16,
        unknown: UInt8 = 0,
        flags: UInt8 = 0,
        associationType: UInt32 = 0,
        byteCount: Int = RelationshipData.byteCount
    ) -> Data {
        var data = Data()
        data.appendUInt32(parent)
        data.appendUInt32(child)
        data.appendUInt16(rank)
        data.append(unknown)
        data.append(flags)
        data.appendUInt32(associationType)
        return ESMFixture.field("DATA", data.prefix(byteCount))
    }

    /// A whole RELA record's bytes: editor ID first, then whatever the caller
    /// appended, in the order the caller gave.
    static func record(
        formID: UInt32,
        editorID: String?,
        headerFlags: UInt32 = 0,
        body: Data = Data()
    ) -> Data {
        var fields = Data()
        if let editorID {
            fields += ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        }
        return ESMFixture.record(
            "RELA",
            formID: formID,
            flags: headerFlags,
            data: fields + body
        )
    }

    /// A whole ASTP record. Each title is dropped when nil, matching a record
    /// that names only the parent side.
    static func associationType(
        formID: UInt32,
        editorID: String?,
        maleParent: String? = nil,
        femaleParent: String? = nil,
        maleChild: String? = nil,
        femaleChild: String? = nil,
        flags: UInt32? = nil,
        extra: Data = Data()
    ) -> Data {
        var fields = Data()
        if let editorID {
            fields += ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        }
        let titles: [(String, String?)] = [
            ("MPRT", maleParent),
            ("FPRT", femaleParent),
            ("MCHT", maleChild),
            ("FCHT", femaleChild)
        ]
        for (type, title) in titles {
            guard let title else { continue }
            fields += ESMFixture.field(type, ESMFixture.zstring(title))
        }
        if let flags {
            var data = Data()
            data.appendUInt32(flags)
            fields += ESMFixture.field("DATA", data)
        }
        return ESMFixture.record("ASTP", formID: formID, data: fields + extra)
    }

    /// A plugin carrying a RELA and an ASTP top group, either of which may be
    /// empty.
    static func plugin(
        masters: [String] = [],
        relationships: [Data] = [],
        associationTypes: [Data] = []
    ) throws -> ESMFile {
        var data = ESMFixture.tes4(masters: masters)
        if !associationTypes.isEmpty {
            data += ESMFixture.topGroup("ASTP", contents: associationTypes.reduce(Data(), +))
        }
        if !relationships.isEmpty {
            data += ESMFixture.topGroup("RELA", contents: relationships.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    /// Parses one fixture record out of its bytes.
    static func decode(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }
}
