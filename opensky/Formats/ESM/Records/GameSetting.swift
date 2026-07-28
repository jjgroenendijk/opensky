// GMST — typed game setting keyed by EDID. The EDID's first character selects
// the DATA representation: s=lstring, i=signed int32, f=float32, b=uint32
// boolean. Unknown prefixes are rejected rather than guessed.
//
// Reference: xEdit Skyrim definitions, wbGMSTUnionDecider + GMST record:
// https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas
// https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas

import Foundation

nonisolated enum GameSettingError: Error, Equatable {
    case expectedGMST(FourCC)
    case missingField(FourCC)
    case duplicateField(FourCC)
    case emptyEditorID
    case unsupportedPrefix(String)
    case invalidDataSize(editorID: String, expected: Int, actual: Int)
    case invalidBoolean(editorID: String, rawValue: UInt32)
    case invalidString(editorID: String)
}

nonisolated struct GameSetting: Equatable {
    enum Value: Equatable {
        case string(LString)
        case integer(Int32)
        case float(Float)
        case boolean(Bool)
    }

    let editorID: String
    let value: Value

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "GMST" else {
            throw GameSettingError.expectedGMST(record.type)
        }
        let fields = try record.fields()
        let editorField = try Self.singleField("EDID", in: fields)
        let dataField = try Self.singleField("DATA", in: fields)
        editorID = try Self.decodeEditorID(editorField)
        value = try Self.decodeValue(dataField, editorID: editorID, localized: localized)
    }

    private static func singleField(_ type: FourCC, in fields: [ESMField]) throws -> ESMField {
        let matches = fields.filter { $0.type == type }
        guard let field = matches.first else {
            throw GameSettingError.missingField(type)
        }
        guard matches.count == 1 else {
            throw GameSettingError.duplicateField(type)
        }
        return field
    }

    private static func decodeEditorID(_ field: ESMField) throws -> String {
        var reader = BinaryReader(field.data)
        guard
            let value = try? reader.readZString(),
            reader.bytesRemaining == 0
        else {
            throw GameSettingError.invalidString(editorID: "EDID")
        }
        guard !value.isEmpty else { throw GameSettingError.emptyEditorID }
        return value
    }

    private static func decodeValue(
        _ field: ESMField,
        editorID: String,
        localized: Bool
    ) throws -> Value {
        switch editorID.first {
        case "s":
            return try .string(decodeString(field, editorID: editorID, localized: localized))
        case "i":
            try requireFourBytes(field, editorID: editorID)
            var reader = BinaryReader(field.data)
            return try .integer(Int32(bitPattern: reader.readUInt32()))
        case "f":
            try requireFourBytes(field, editorID: editorID)
            var reader = BinaryReader(field.data)
            return try .float(reader.readFloat32())
        case "b":
            try requireFourBytes(field, editorID: editorID)
            var reader = BinaryReader(field.data)
            let rawValue = try reader.readUInt32()
            guard rawValue <= 1 else {
                throw GameSettingError.invalidBoolean(editorID: editorID, rawValue: rawValue)
            }
            return .boolean(rawValue == 1)
        default:
            throw GameSettingError.unsupportedPrefix(String(editorID.prefix(1)))
        }
    }

    private static func requireFourBytes(_ field: ESMField, editorID: String) throws {
        guard field.data.count == 4 else {
            throw GameSettingError.invalidDataSize(
                editorID: editorID,
                expected: 4,
                actual: field.data.count
            )
        }
    }

    private static func decodeString(
        _ field: ESMField,
        editorID: String,
        localized: Bool
    ) throws -> LString {
        if localized {
            try requireFourBytes(field, editorID: editorID)
            return try LString(field: field, localized: true)
        }
        var reader = BinaryReader(field.data)
        guard
            let bytes = try? reader.readZStringData(),
            reader.bytesRemaining == 0,
            let string = GameText.decode(bytes)
        else {
            throw GameSettingError.invalidString(editorID: editorID)
        }
        return .inline(string)
    }
}
