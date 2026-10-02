// Field access for record decoders. Each read marks its field as used, and
// `finish()` tallies every field nobody read. A field whose decode throws is
// tallied as malformed and reads as nil, so a bad field costs only itself.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct RecordFields {
    public let formID: FormID
    public let recordType: FourCC
    /// The TES4 localized flag of the plugin that holds the record.
    public let localized: Bool
    public let fields: [ESMField]
    private var used: [Bool]
    private var tally = FieldTally()

    public init(record: ESMRecord, type: FourCC, localized: Bool = false) throws {
        try self.init(record: record, types: [type], localized: localized)
    }

    /// Throws only when the record has another type or its field list does not parse.
    public init(record: ESMRecord, types: Set<FourCC>, localized: Bool = false) throws {
        guard types.contains(record.type) else {
            let wanted = types.map(\.description).sorted().joined(separator: "/")
            throw ESMError.malformed("expected \(wanted) record, got \(record.type)")
        }
        formID = FormID(record.formID)
        recordType = record.type
        self.localized = localized
        fields = try record.fields()
        used = Array(repeating: false, count: fields.count)
    }

    // MARK: - Generic reads

    /// Decodes the first unused field of `type`.
    public mutating func read<Value>(
        _ type: FourCC,
        _ decode: (inout BinaryReader) throws -> Value
    ) -> Value? {
        guard let index = firstUnused(type) else { return nil }
        return read(at: index, decode)
    }

    /// Decodes every unused field of `type`, in file order. A malformed one is left out.
    public mutating func readAll<Value>(
        _ type: FourCC,
        _ decode: (inout BinaryReader) throws -> Value
    ) -> [Value] {
        fields.indices.filter { fields[$0].type == type && !used[$0] }
            .compactMap { read(at: $0, decode) }
    }

    /// Decodes the field at `index` and marks it used, whatever its type.
    public mutating func read<Value>(
        at index: Int,
        _ decode: (inout BinaryReader) throws -> Value
    ) -> Value? {
        used[index] = true
        var reader = BinaryReader(fields[index].data)
        do {
            return try decode(&reader)
        } catch {
            tally.note(.malformedField(fields[index].type))
            return nil
        }
    }

    /// Marks the field at `index` used without decoding it.
    public mutating func markUsed(at index: Int) {
        used[index] = true
    }

    public func isUsed(at index: Int) -> Bool {
        used[index]
    }

    public mutating func note(_ kind: FieldSkipKind) {
        tally.note(kind)
    }

    /// The tally, with one `unknownField` entry for every field nobody read.
    public mutating func finish() -> FieldTally {
        for index in fields.indices where !used[index] {
            tally.note(.unknownField(fields[index].type))
            used[index] = true
        }
        return tally
    }

    private func firstUnused(_ type: FourCC) -> Int? {
        fields.indices.first { fields[$0].type == type && !used[$0] }
    }
}

// MARK: - Typed reads

nonisolated extension RecordFields {
    public mutating func editorID() -> String? {
        zstring("EDID")
    }

    public mutating func zstring(_ type: FourCC) -> String? {
        read(type) { try $0.readZString() }
    }

    public mutating func lstring(_ type: FourCC) -> LString? {
        guard let index = firstUnused(type) else { return nil }
        let localized = localized
        let field = fields[index]
        return read(at: index) { _ in try LString(field: field, localized: localized) }
    }

    /// A FormID field. A null FormID reads as nil.
    public mutating func formID(_ type: FourCC) -> FormID? {
        read(type) { try FormID($0.readUInt32()) }.flatMap(\.nonNull)
    }

    /// Every field of a repeated FormID field, nulls kept.
    public mutating func formIDs(_ type: FourCC) -> [FormID] {
        readAll(type) { try FormID($0.readUInt32()) }
    }

    /// One field that packs an array of FormIDs. A tail under 4 bytes is dropped.
    public mutating func formIDArray(_ type: FourCC) -> [FormID] {
        read(type) { reader in
            var ids: [FormID] = []
            while reader.bytesRemaining >= 4 {
                try ids.append(FormID(reader.readUInt32()))
            }
            return ids
        } ?? []
    }

    public mutating func uint8(_ type: FourCC) -> UInt8? {
        read(type) { try $0.readUInt8() }
    }

    public mutating func uint16(_ type: FourCC) -> UInt16? {
        read(type) { try $0.readUInt16() }
    }

    public mutating func uint32(_ type: FourCC) -> UInt32? {
        read(type) { try $0.readUInt32() }
    }

    public mutating func float(_ type: FourCC) -> Float? {
        read(type) { try $0.readFloat32() }
    }

    /// The raw bytes of a field whose meaning no spec makes clear.
    public mutating func bytes(_ type: FourCC) -> Data? {
        read(type) { try $0.read(count: $0.bytesRemaining) }
    }

    /// True when the record carries a field of `type`; used for empty marker fields.
    public mutating func marker(_ type: FourCC) -> Bool {
        read(type) { _ in true } ?? false
    }

    public mutating func bounds() -> ObjectBounds? {
        guard let index = firstUnused("OBND") else { return nil }
        let field = fields[index]
        return read(at: index) { _ in try ObjectBounds(field: field) }
    }

    /// The record's single condition run (CITC, CTDA, CIS1, CIS2).
    public mutating func conditions() -> [Condition] {
        var list = ConditionList()
        for index in fields.indices where !used[index] {
            let field = fields[index]
            guard ConditionList.isConditionField(field.type) else { continue }
            _ = read(at: index) { _ in try list.decode(field: field) }
        }
        return list.conditions
    }

    /// A model group: path, texture hashes, and alternate textures.
    public mutating func model(
        path: FourCC = "MODL",
        hashes: FourCC = "MODT",
        alternates: FourCC = "MODS"
    ) -> ModelData? {
        guard let index = firstUnused(path) else { return nil }
        return model(at: index, hashes: hashes, alternates: alternates)
    }

    /// The model group whose path field sits at `index`. Hashes and alternates
    /// belong to it only when they follow the path directly.
    public mutating func model(
        at index: Int,
        hashes: FourCC = "MODT",
        alternates: FourCC = "MODS"
    ) -> ModelData? {
        guard let modelPath = read(at: index, { try $0.readZString() }) else { return nil }
        var hashData: Data?
        var alternateTextures: [ModelData.AlternateTexture]?
        var next = index + 1
        while next < fields.count, !used[next] {
            let type = fields[next].type
            if type == hashes, hashData == nil {
                hashData = read(at: next) { try $0.read(count: $0.bytesRemaining) }
            } else if type == alternates, alternateTextures == nil {
                alternateTextures = read(at: next) { try ModelData.alternateTextures(&$0) } ?? []
            } else {
                break
            }
            next += 1
        }
        return ModelData(
            path: modelPath,
            textureHashes: hashData,
            alternateTextures: alternateTextures ?? []
        )
    }
}

nonisolated extension FormID {
    /// Nil for the null FormID.
    public var nonNull: FormID? {
        isNull ? nil : self
    }
}

nonisolated extension BinaryReader {
    public mutating func readInt32() throws -> Int32 {
        try Int32(bitPattern: readUInt32())
    }

    public mutating func readInt16() throws -> Int16 {
        try Int16(bitPattern: readUInt16())
    }

    public mutating func readInt8() throws -> Int8 {
        try Int8(bitPattern: readUInt8())
    }

    public mutating func readFormID() throws -> FormID {
        try FormID(readUInt32())
    }

    public mutating func readFloat3() throws -> SIMD3<Float> {
        try SIMD3(readFloat32(), readFloat32(), readFloat32())
    }
}

nonisolated extension RecordFields {
    /// Every VMAD field, decoded for a carrier of this record's type.
    public mutating func scriptData() -> ScriptData {
        var data = ScriptData(ownerType: recordType)
        for index in fields.indices where fields[index].type == "VMAD" && !isUsed(at: index) {
            let field = fields[index]
            _ = read(at: index) { _ in try data.decode(field: field) }
        }
        return data
    }
}
