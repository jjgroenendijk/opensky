// Synthetic QUST builder: record fields and the VMAD quest fragment tail.
// Layout: docs/formats/quest-records.md.

import Foundation
@testable import OpenSkyFormatsESM

public enum QuestFixture: Sendable {
    // MARK: - Record assembly

    public static func record(formID: UInt32 = 0x0100, fields: Data) -> Data {
        ESMFixture.record("QUST", formID: formID, data: fields)
    }

    /// First record parsed out of raw fixture bytes.
    public static func parse(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    public static func quest(formID: UInt32 = 0x0100, fields: Data) throws -> Quest {
        try Quest(record: parse(record(formID: formID, fields: fields)))
    }

    /// Plugin carrying a TES4 header and one QUST top group.
    public static func plugin(_ records: Data) -> Data {
        ESMFixture.tes4() + ESMFixture.topGroup("QUST", contents: records)
    }

    // MARK: - Quest-level fields

    public static func editorID(_ value: String) -> Data {
        ESMFixture.field("EDID", ESMFixture.zstring(value))
    }

    public static func full(_ value: String) -> Data {
        ESMFixture.field("FULL", ESMFixture.zstring(value))
    }

    /// DNAM: uint16 flags, uint8 priority, uint8 form version, 4 unused bytes,
    /// uint32 quest type.
    public static func general(flags: UInt16 = 0, priority: UInt8 = 0, type: UInt32 = 0) -> Data {
        var data = Data()
        data.appendUInt16(flags)
        data.append(priority)
        data.append(0) // form version
        data.appendUInt32(0) // unused
        data.appendUInt32(type)
        return ESMFixture.field("DNAM", data)
    }

    public static func word(_ type: String, _ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return ESMFixture.field(type, data)
    }

    public static func signedWord(_ type: String, _ value: Int32) -> Data {
        word(type, UInt32(bitPattern: value))
    }

    public static func marker(_ type: String) -> Data {
        ESMFixture.field(type, Data())
    }

    /// CTDA, 32 bytes. Only the fields the quest tests read are parameterised.
    public static func condition(functionIndex: UInt16, parameter1: UInt32 = 0) -> Data {
        var data = Data([0, 0, 0, 0])
        data.appendUInt32(0) // comparison value
        data.appendUInt16(functionIndex)
        data.appendUInt16(0) // padding
        data.appendUInt32(parameter1)
        data.appendUInt32(0) // parameter 2
        data.appendUInt32(0) // run on
        data.appendUInt32(0) // reference
        data.appendUInt32(UInt32(bitPattern: -1)) // parameter 3
        return ESMFixture.field("CTDA", data)
    }

    // MARK: - Stages

    /// INDX: uint16 stage index, uint8 flags, 1 unused byte.
    public static func stage(_ index: UInt16, flags: UInt8 = 0) -> Data {
        var data = Data()
        data.appendUInt16(index)
        data.append(flags)
        data.append(0)
        return ESMFixture.field("INDX", data)
    }

    public static func logEntry(flags: UInt8 = 0, text: String? = nil) -> Data {
        var data = ESMFixture.field("QSDT", Data([flags]))
        if let text {
            data += ESMFixture.field("CNAM", ESMFixture.zstring(text))
        }
        return data
    }

    // MARK: - Objectives

    public static func objective(_ index: UInt16, flags: UInt32 = 0, text: String? = nil) -> Data {
        var indexData = Data()
        indexData.appendUInt16(index)
        var data = ESMFixture.field("QOBJ", indexData)
        data += word("FNAM", flags)
        if let text {
            data += ESMFixture.field("NNAM", ESMFixture.zstring(text))
        }
        return data
    }

    /// QSTA, 8 bytes: int32 alias or reference, uint8 ignores-locks, 3 unused.
    public static func target(alias: Int32, ignoresLocks: Bool = false) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(bitPattern: alias))
        data.append(ignoresLocks ? 1 : 0)
        data.append(contentsOf: [0, 0, 0])
        return ESMFixture.field("QSTA", data)
    }

    // MARK: - Aliases

    /// A complete ALST/ALLS ... ALED group.
    public static func alias(
        id: UInt32,
        name: String,
        location: Bool = false,
        flags: UInt32 = 0,
        fill: Data = Data(),
        extras: Data = Data(),
        terminated: Bool = true
    ) -> Data {
        var data = word(location ? "ALLS" : "ALST", id)
        data += ESMFixture.field("ALID", ESMFixture.zstring(name))
        data += word("FNAM", flags)
        data += fill
        data += extras
        if terminated {
            data += marker("ALED")
        }
        return data
    }

    // MARK: - VMAD quest tail

    public struct Fragment: Sendable {
        public let stage: UInt16
        public let logEntry: Int32
        public let script: String
        public let function: String

        public init(stage: UInt16, logEntry: Int32 = 0, script: String, function: String) {
            self.stage = stage
            self.logEntry = logEntry
            self.script = script
            self.function = function
        }
    }

    public struct AliasScripts: Sendable {
        public let object: ScriptObjectReference
        public let scripts: [VMADFixture.Script]

        public init(object: ScriptObjectReference, scripts: [VMADFixture.Script]) {
            self.object = object
            self.scripts = scripts
        }
    }

    /// The QUST fragment tail: int8 bind version, uint16 fragment count,
    /// wstring file name, the fragment table, then the alias-script array.
    public static func fragmentTail(
        bindVersion: Int8 = 2,
        declaredCount: UInt16? = nil,
        fileName: String,
        fragments: [Fragment],
        aliases: [AliasScripts] = [],
        version: Int16 = 5,
        objectFormat: ScriptObjectFormat = .formIDLast,
        includeAliasCount: Bool = true
    ) -> Data {
        var data = Data([UInt8(bitPattern: bindVersion)])
        data.appendUInt16(declaredCount ?? UInt16(fragments.count))
        data.appendQuestString(fileName)
        for fragment in fragments {
            data.appendUInt16(fragment.stage)
            data.appendUInt16(0) // always zero
            data.appendUInt32(UInt32(bitPattern: fragment.logEntry))
            data.append(1) // always one
            data.appendQuestString(fragment.script)
            data.appendQuestString(fragment.function)
        }
        guard includeAliasCount else { return data }
        data.appendUInt16(UInt16(aliases.count))
        for alias in aliases {
            data.appendQuestObject(alias.object, objectFormat: objectFormat)
            data.appendUInt16(UInt16(bitPattern: version))
            data.appendUInt16(UInt16(bitPattern: objectFormat.rawValue))
            data.append(VMADFixture.scriptArray(
                alias.scripts,
                version: version,
                objectFormat: objectFormat
            ))
        }
        return data
    }

    /// A VMAD field carrying the primary script list plus a quest tail.
    public static func vmad(
        scripts: [VMADFixture.Script] = [],
        tail: Data,
        objectFormat: ScriptObjectFormat = .formIDLast
    ) -> Data {
        ESMFixture.field(
            "VMAD",
            VMADFixture.payload(objectFormat: objectFormat, scripts: scripts, tail: tail)
        )
    }
}

extension Data {
    public mutating func appendQuestString(_ value: String) {
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count))
        append(bytes)
    }

    public mutating func appendQuestObject(
        _ object: ScriptObjectReference,
        objectFormat: ScriptObjectFormat
    ) {
        switch objectFormat {
        case .formIDFirst:
            appendUInt32(object.formID.rawValue)
            appendUInt16(UInt16(bitPattern: object.alias))
            appendUInt16(object.unused)
        case .formIDLast:
            appendUInt16(object.unused)
            appendUInt16(UInt16(bitPattern: object.alias))
            appendUInt32(object.formID.rawValue)
        }
    }
}
