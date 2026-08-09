// Stateful PACK field walk. The same subrecord names are reused in the
// header, public-data section and procedure tree, so section position is part
// of the format and one flat switch would silently misclassify them.

import Foundation

nonisolated enum PackageDecoder {
    private enum Section {
        case header
        case publicData
        case procedureTree
        case tail
    }

    private struct State {
        var section = Section.header
        var editorID: String?
        var general: Package.GeneralData?
        var schedule: Package.Schedule?
        var conditions = ConditionList()
        var template: FormID?
        var pendingType: String?
        var inputs: [(type: String, value: Package.DataValue)] = []
        var indexes: [Int8] = []
        var procedureTypes: [String] = []
        var scriptData = ScriptData(ownerType: "PACK")
    }

    static func decode(_ record: ESMRecord) throws -> Package {
        guard record.type == "PACK" else {
            throw ESMError.malformed("expected PACK record, got \(record.type)")
        }
        var state = State()
        for field in try record.fields() {
            try decode(field, into: &state)
        }
        let formID = FormID(record.formID)
        guard let general = state.general else {
            throw ESMError.malformed("PACK \(formID) has no PKDT field")
        }
        guard let schedule = state.schedule else {
            throw ESMError.malformed("PACK \(formID) has no PSDT field")
        }
        return Package(
            formID: formID,
            editorID: state.editorID,
            general: general,
            schedule: schedule,
            conditions: state.conditions,
            template: state.template,
            dataInputs: zipInputs(state.inputs, indexes: state.indexes),
            procedureTypes: state.procedureTypes,
            scriptData: state.scriptData
        )
    }

    private static func decode(_ field: ESMField, into state: inout State) throws {
        switch state.section {
        case .header:
            try decodeHeader(field, into: &state)
        case .publicData:
            try decodePublicData(field, into: &state)
        case .procedureTree:
            try decodeProcedureTree(field, into: &state)
        case .tail:
            _ = try state.scriptData.decode(field: field)
        }
    }

    private static func decodeHeader(_ field: ESMField, into state: inout State) throws {
        var reader = BinaryReader(field.data)
        switch field.type {
        case "EDID":
            state.editorID = try reader.readZString()
        case "PKDT":
            state.general = try generalData(field)
        case "PSDT":
            state.schedule = try schedule(field)
        case "PKCU":
            guard field.data.count == 12 else {
                throw ESMError.malformed("PACK PKCU has \(field.data.count) bytes, expected 12")
            }
            _ = try reader.readUInt32()
            let rawTemplate = try reader.readUInt32()
            state.template = rawTemplate == 0 ? nil : FormID(rawTemplate)
            _ = try reader.readUInt32()
            state.section = .publicData
        default:
            if try !state.conditions.decode(field: field) {
                _ = try state.scriptData.decode(field: field)
            }
        }
    }

    private static func decodePublicData(_ field: ESMField, into state: inout State) throws {
        var reader = BinaryReader(field.data)
        switch field.type {
        case "ANAM":
            state.pendingType = try reader.readZString()
        case "CNAM", "PLDT", "PTDA", "PDTO", "TPIC":
            try appendValue(field, into: &state)
        case "UNAM":
            try state.indexes.append(Int8(bitPattern: reader.readUInt8()))
        case "XNAM":
            state.pendingType = nil
            state.section = .procedureTree
        default:
            _ = try state.scriptData.decode(field: field)
        }
    }

    private static func decodeProcedureTree(_ field: ESMField, into state: inout State) throws {
        var reader = BinaryReader(field.data)
        switch field.type {
        case "PNAM" where field.data.count > 4:
            try state.procedureTypes.append(reader.readZString())
        case "POBA", "POEA", "POCA":
            state.section = .tail
        default:
            break
        }
    }

    private static func generalData(_ field: ESMField) throws -> Package.GeneralData {
        guard field.data.count == 12 else {
            throw ESMError.malformed("PACK PKDT has \(field.data.count) bytes, expected 12")
        }
        var reader = BinaryReader(field.data)
        let flags = try Package.GeneralFlags(rawValue: reader.readUInt32())
        let kind = try Package.Kind(rawValue: reader.readUInt8())
        let interrupt = try reader.readUInt8()
        let speed = try Package.PreferredSpeed(rawValue: reader.readUInt8())
        reader.skip(1)
        let interruptFlags = try reader.readUInt16()
        return Package.GeneralData(
            flags: flags,
            kind: kind,
            interruptOverride: interrupt,
            preferredSpeed: speed,
            interruptFlags: interruptFlags
        )
    }

    private static func schedule(_ field: ESMField) throws -> Package.Schedule {
        guard field.data.count == 12 else {
            throw ESMError.malformed("PACK PSDT has \(field.data.count) bytes, expected 12")
        }
        var reader = BinaryReader(field.data)
        let month = try Int8(bitPattern: reader.readUInt8())
        let weekday = try Int8(bitPattern: reader.readUInt8())
        let date = try Int8(bitPattern: reader.readUInt8())
        let hour = try Int8(bitPattern: reader.readUInt8())
        let minute = try Int8(bitPattern: reader.readUInt8())
        reader.skip(3)
        return try Package.Schedule(
            month: month,
            dayOfWeek: weekday,
            date: date,
            hour: hour,
            minute: minute,
            durationMinutes: reader.readUInt32()
        )
    }

    private static func appendValue(_ field: ESMField, into state: inout State) throws {
        guard let type = state.pendingType else { return }
        try state.inputs.append((type, value(field, type: type)))
        state.pendingType = nil
    }

    private static func value(_ field: ESMField, type: String) throws -> Package.DataValue {
        var reader = BinaryReader(field.data)
        switch (type, field.type) {
        case ("Bool", "CNAM"):
            return try .boolean(reader.readUInt8() != 0)
        case ("Int", "CNAM"):
            return try .integer(Int32(bitPattern: reader.readUInt32()))
        case ("Float", "CNAM"), ("ObjectList", "CNAM"):
            return try .float(reader.readFloat32())
        case ("Location", "PLDT"):
            return try .location(location(&reader, field: field))
        case ("SingleRef", "PTDA"), ("TargetSelector", "PTDA"):
            return try .target(target(&reader, field: field))
        case ("Topic", "TPIC"):
            return try .topic(FormID(reader.readUInt32()))
        case ("Topic", "PDTO"):
            guard field.data.count == 8 else {
                throw ESMError.malformed("PACK PDTO has \(field.data.count) bytes, expected 8")
            }
            let kind = try reader.readUInt32()
            let raw = try reader.readUInt32()
            return kind == 0 ? .topic(FormID(raw)) : .unknown(type: type, bytes: 8)
        default:
            return .unknown(type: type, bytes: field.data.count)
        }
    }

    private static func location(
        _ reader: inout BinaryReader,
        field: ESMField
    ) throws -> Package.Location {
        guard field.data.count == 12 else {
            throw ESMError.malformed("PACK PLDT has \(field.data.count) bytes, expected 12")
        }
        return try Package.Location(
            rawKind: Int32(bitPattern: reader.readUInt32()),
            value: reader.readUInt32(),
            radius: Int32(bitPattern: reader.readUInt32())
        )
    }

    private static func target(
        _ reader: inout BinaryReader,
        field: ESMField
    ) throws -> Package.Target {
        guard field.data.count == 12 else {
            throw ESMError.malformed("PACK PTDA has \(field.data.count) bytes, expected 12")
        }
        return try Package.Target(
            rawKind: Int32(bitPattern: reader.readUInt32()),
            value: reader.readUInt32(),
            countOrDistance: Int32(bitPattern: reader.readUInt32())
        )
    }

    private static func zipInputs(
        _ values: [(type: String, value: Package.DataValue)],
        indexes: [Int8]
    ) -> [Package.DataInput] {
        values.enumerated().map { offset, entry in
            Package.DataInput(
                index: indexes.indices.contains(offset) ? indexes[offset] : nil,
                type: entry.type,
                value: entry.value
            )
        }
    }
}
