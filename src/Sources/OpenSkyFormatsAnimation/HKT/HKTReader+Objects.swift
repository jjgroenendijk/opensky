// The object half of the tagfile item stream: objects, values, and struct columns.
// Layout: docs/formats/hkt-tagfile.md.

import Foundation
import OpenSkyFormatsCore

nonisolated extension HKTReader {
    mutating func readObject(remember: Bool) throws -> Int {
        let offset = reader.offset
        let index = try readInt()
        guard index > 0, classes.indices.contains(index) else {
            throw HKTError.badClassIndex(index, offset: offset)
        }
        if remember {
            remembered.append(nil)
        }
        let slot = remembered.count - 1
        let fields = try readFields(classIndex: index)
        objects.append(fields)
        if remember {
            remembered[slot] = objects.count - 1
        }
        return objects.count - 1
    }

    private mutating func presenceMask(count: Int) throws -> [Bool] {
        let bytes = try readRaw { try $0.read(count: (count + 7) / 8) }
        return (0 ..< count).map { bit in
            bytes[bytes.startIndex + bit / 8] & UInt8(1 << (bit % 8)) != 0
        }
    }

    private mutating func readFields(classIndex: Int) throws -> HKTFields {
        depth += 1
        defer { depth -= 1 }
        guard depth <= Self.maximumDepth else {
            throw HKTError.nestingTooDeep(offset: reader.offset)
        }
        let members = members(ofClass: classIndex)
        let present = try presenceMask(count: members.count)
        var values: [(name: String, value: HKTValue)] = []
        for (member, isPresent) in zip(members, present) where isPresent {
            try values.append((member.name, readValue(member.type)))
        }
        return HKTFields(classIndex: classIndex, values: values)
    }

    private mutating func readValue(_ type: HKTMemberType) throws -> HKTValue {
        if type.isArray {
            let count = try readCount()
            if let tuple = type.tupleCount {
                return try .array((0 ..< count).map { _ in try .array(readElements(type, tuple)) })
            }
            return try .array(readElements(type, count))
        }
        if let tuple = type.tupleCount {
            return try .array(readElements(type, tuple))
        }
        return try readScalar(type)
    }

    private mutating func readScalar(_ type: HKTMemberType) throws -> HKTValue {
        switch type.base {
        case .void:
            return .array([])
        case .byte:
            return try .byte(readRaw { try $0.readUInt8() })
        case .int:
            return try .int(readInt64())
        case .real:
            return try .real(readRaw { try $0.readFloat32() })
        case .vector4, .vector8, .vector12, .vector16:
            let length = type.base.vectorLength ?? 0
            return try .vector((0 ..< length).map { _ in try readRaw { try $0.readFloat32() } })
        case .object:
            return try .reference(readReference())
        case .structure:
            return try .structure(readFields(classIndex: classIndex(
                named: type.className, offset: reader.offset
            )))
        case .string:
            return try .string(readString())
        }
    }

    /// A version 0 file writes the object, a back reference, or null in place.
    private mutating func readReference() throws -> HKTReference {
        guard version == 0 else {
            let index = try readInt()
            return index == 0 ? .null : .remembered(index)
        }
        let offset = reader.offset
        let raw = try readInt()
        switch Tag(rawValue: raw) {
        case .object, .rememberedObject:
            return try .object(readObject(remember: raw == Tag.rememberedObject.rawValue))
        case .backReference:
            return try .remembered(readInt())
        case .null:
            return .null
        default:
            throw HKTError.unknownTag(raw, offset: offset)
        }
    }

    /// `count` values of one type, as an array or as one struct-array column.
    private mutating func readElements(_ type: HKTMemberType, _ count: Int) throws -> [HKTValue] {
        switch type.base {
        case .structure:
            return try readStructColumns(type, count)
        case .int:
            if count > 0, version != 0, try readInt() != 4 {
                unexpectedIntArrayHeaders += 1
            }
            return try (0 ..< count).map { _ in try .int(readInt64()) }
        default:
            let scalar = HKTMemberType(
                base: type.base, isArray: false, tupleCount: nil, className: type.className
            )
            return try (0 ..< count).map { _ in try readScalar(scalar) }
        }
    }

    /// A struct array stores one presence mask, then each present member as a
    /// column over every element.
    private mutating func readStructColumns(
        _ type: HKTMemberType,
        _ count: Int
    ) throws -> [HKTValue] {
        let index = try classIndex(named: type.className, offset: reader.offset)
        let members = members(ofClass: index)
        let present = try presenceMask(count: members.count)
        var rows = [[(name: String, value: HKTValue)]](repeating: [], count: count)
        for (member, isPresent) in zip(members, present) where isPresent {
            let column = try readColumn(member.type, count)
            for row in 0 ..< count {
                rows[row].append((member.name, column[row]))
            }
        }
        return rows.map { .structure(HKTFields(classIndex: index, values: $0)) }
    }

    private mutating func readColumn(_ type: HKTMemberType, _ count: Int) throws -> [HKTValue] {
        if type.isArray {
            return try (0 ..< count).map { _ in try readValue(type) }
        }
        if let tuple = type.tupleCount {
            return try (0 ..< count).map { _ in try .array(readElements(type, tuple)) }
        }
        return try readElements(type, count)
    }
}
