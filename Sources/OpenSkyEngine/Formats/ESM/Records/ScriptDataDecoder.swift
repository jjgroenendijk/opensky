// Bounds-checked VMAD primary-script decoder. See ScriptData.swift for sources.

import Foundation

nonisolated extension ScriptData {
    /// Consumes `field` when it is VMAD. Returns false for anything else so
    /// record decoders can forward unmatched fields without a second switch.
    @discardableResult
    mutating func decode(field: ESMField) throws -> Bool {
        guard field.type == "VMAD" else { return false }
        do {
            var decoder = ScriptDataDecoder(data: field.data, ownerType: ownerType)
            let payload = try decoder.decode()
            version = payload.version
            objectFormat = payload.objectFormat
            scripts.append(contentsOf: payload.scripts)
            questFragments = payload.questFragments ?? questFragments
            infoFragments = payload.infoFragments ?? infoFragments
            skipped.merge(payload.skipped)
            return true
        } catch let error as ScriptDataError {
            throw error
        } catch let error as BinaryReaderError {
            throw ScriptDataError.binary(error)
        }
    }
}

nonisolated struct ScriptDataPayload {
    let version: Int16
    let objectFormat: ScriptObjectFormat
    let scripts: [AttachedScript]
    let questFragments: QuestFragmentSection?
    let infoFragments: TopicInfoFragmentSection?
    let skipped: ScriptDataTally
}

/// Not `private`: the QUST fragment tail is decoded by an extension in
/// ScriptDataQuestFragmentDecoder.swift, which needs the reader and the
/// primary script, property and object readers this type owns.
nonisolated struct ScriptDataDecoder {
    /// Carriers whose VMAD may end in a record-specific fragment tail. QUST
    /// (`ScriptDataQuestFragments.swift`) and INFO
    /// (`ScriptDataInfoFragments.swift`) are decoded; the other three are still
    /// recorded and skipped, so they stay in the set.
    private static let fragmentRecordTypes: Set<FourCC> = [
        "INFO", "PACK", "PERK", "QUST", "SCEN"
    ]

    var reader: BinaryReader
    let ownerType: FourCC?
    var version: Int16 = 0
    var objectFormat: ScriptObjectFormat = .formIDLast
    var questFragments: QuestFragmentSection?
    var infoFragments: TopicInfoFragmentSection?
    var skipped = ScriptDataTally()

    init(data: Data, ownerType: FourCC?) {
        reader = BinaryReader(data)
        self.ownerType = ownerType
    }

    mutating func decode() throws -> ScriptDataPayload {
        version = try Int16(bitPattern: reader.readUInt16())
        guard (2 ... 5).contains(version) else {
            throw ScriptDataError.unsupportedVersion(version)
        }
        let rawObjectFormat = try Int16(bitPattern: reader.readUInt16())
        guard let format = ScriptObjectFormat(rawValue: rawObjectFormat) else {
            throw ScriptDataError.unsupportedObjectFormat(rawObjectFormat)
        }
        objectFormat = format

        let scriptCount = try checkedCount(
            UInt32(reader.readUInt16()),
            minimumSize: version >= 4 ? 5 : 4,
            context: "scripts"
        )
        var scripts: [AttachedScript] = []
        scripts.reserveCapacity(scriptCount)
        for _ in 0 ..< scriptCount {
            try scripts.append(decodeScript())
        }
        try consumeFragmentTail()
        return ScriptDataPayload(
            version: version,
            objectFormat: objectFormat,
            scripts: scripts,
            questFragments: questFragments,
            infoFragments: infoFragments,
            skipped: skipped
        )
    }

    mutating func decodeScript() throws -> AttachedScript {
        let name = try readString()
        let flags = version >= 4 ? try AttachedScript.Flags(rawValue: reader.readUInt8()) : []
        let propertyCount = try checkedCount(
            UInt32(reader.readUInt16()),
            minimumSize: version >= 4 ? 4 : 3,
            context: "properties"
        )
        var properties: [ScriptProperty] = []
        properties.reserveCapacity(propertyCount)
        for _ in 0 ..< propertyCount {
            try properties.append(decodeProperty())
        }
        return AttachedScript(name: name, flags: flags, properties: properties)
    }

    private mutating func decodeProperty() throws -> ScriptProperty {
        let name = try readString()
        let type = try reader.readUInt8()
        let flags = version >= 4 ? try ScriptProperty.Flags(rawValue: reader.readUInt8()) : .edited
        if flags.contains(.removed) {
            skipped.note(.removedProperty)
        }
        return try ScriptProperty(
            name: name,
            type: type,
            flags: flags,
            value: decodeValue(type: type)
        )
    }

    private mutating func decodeValue(type: UInt8) throws -> ScriptPropertyValue {
        switch type {
        case 0:
            return .none
        case 1:
            return try .object(decodeObject())
        case 2:
            return try .string(readString())
        case 3:
            return try .integer(Int32(bitPattern: reader.readUInt32()))
        case 4:
            return try .float(reader.readFloat32())
        case 5:
            return try .boolean(reader.readUInt8() != 0)
        case 11 ... 15:
            guard version >= 5 else {
                throw ScriptDataError.arrayRequiresVersionFive(type: type, version: version)
            }
            return try decodeArray(type: type)
        default:
            throw ScriptDataError.unknownPropertyType(type)
        }
    }

    private mutating func decodeArray(type: UInt8) throws -> ScriptPropertyValue {
        let minimumSize = switch type {
        case 11:
            8
        case 12:
            2
        case 13, 14:
            4
        default:
            1
        }
        let count = try checkedCount(
            reader.readUInt32(),
            minimumSize: minimumSize,
            context: "property array"
        )
        switch type {
        case 11:
            return try .objects((0 ..< count).map { _ in try decodeObject() })
        case 12:
            return try .strings((0 ..< count).map { _ in try readString() })
        case 13:
            return try .integers((0 ..< count).map { _ in
                try Int32(bitPattern: reader.readUInt32())
            })
        case 14:
            return try .floats((0 ..< count).map { _ in try reader.readFloat32() })
        default:
            return try .booleans((0 ..< count).map { _ in try reader.readUInt8() != 0 })
        }
    }

    /// - Parameter notingAlias: false for the object that opens a quest-alias
    ///   script section, where an alias slot is the whole point rather than a
    ///   deferred resolution the tally exists to count.
    mutating func decodeObject(notingAlias: Bool = true) throws -> ScriptObjectReference {
        let formID: FormID
        let alias: Int16
        let unused: UInt16
        switch objectFormat {
        case .formIDFirst:
            formID = try FormID(reader.readUInt32())
            alias = try Int16(bitPattern: reader.readUInt16())
            unused = try reader.readUInt16()
        case .formIDLast:
            unused = try reader.readUInt16()
            alias = try Int16(bitPattern: reader.readUInt16())
            formID = try FormID(reader.readUInt32())
        }
        let object = ScriptObjectReference(formID: formID, alias: alias, unused: unused)
        if notingAlias, object.isAlias {
            skipped.note(.aliasObject)
        }
        return object
    }

    /// Length-prefixed VMAD string; decodes under the engine-wide `GameText`
    /// policy, so only the length prefix can fail the read.
    mutating func readString() throws -> String {
        let length = try Int(reader.readUInt16())
        return try GameText.decode(reader.read(count: length))
    }

    func checkedCount(
        _ count: UInt32,
        minimumSize: Int,
        context: String
    ) throws -> Int {
        let maximum = reader.bytesRemaining / minimumSize
        guard count <= UInt32(maximum) else {
            throw ScriptDataError.impossibleCount(
                context: context,
                count: count,
                remaining: reader.bytesRemaining
            )
        }
        return Int(count)
    }

    private mutating func consumeFragmentTail() throws {
        guard reader.bytesRemaining > 0 else { return }
        guard let ownerType, Self.fragmentRecordTypes.contains(ownerType) else {
            throw ScriptDataError.unexpectedTrailingBytes(
                recordType: ownerType,
                count: reader.bytesRemaining
            )
        }
        if ownerType == "QUST", decodeQuestFragmentTail() {
            return
        }
        if ownerType == "INFO", decodeInfoFragmentTail() {
            return
        }
        skipped.note(.fragments(ownerType))
        reader.skip(reader.bytesRemaining)
    }
}
