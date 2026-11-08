// The item stream of a Havok binary tagfile. Every number is a varint whose low
// bit is the sign. A struct array stores one column per member.
// Layout: docs/formats/hkt-tagfile.md.

import Foundation
import OpenSkyFormatsCore

nonisolated struct HKTReader {
    enum Tag: Int {
        case fileInfo = 1
        case metadata = 2
        case object = 3
        case rememberedObject = 4
        case backReference = 5
        case null = 6
        case end = 7
    }

    static let maximumDepth = 64

    var reader: BinaryReader
    let size: Int
    var strings: [String?] = ["", nil]
    var depth = 0
    var version = 0
    var classes: [HKTClass] = [HKTClass(name: "", version: 0, parent: nil, members: [])]
    var objects: [HKTFields] = []
    var remembered: [Int?] = [nil]
    var sawEndTag = false
    var unexpectedIntArrayHeaders = 0

    init(data: Data) {
        reader = BinaryReader(data)
        size = data.count
    }

    mutating func readMagic() throws {
        let first = try readRaw { try $0.readUInt32() }
        let second = try readRaw { try $0.readUInt32() }
        guard first == HKTagfile.magic0, second == HKTagfile.magic1 else {
            throw HKTError.badMagic(found0: first, found1: second)
        }
    }

    mutating func readItems() throws {
        while reader.offset < size {
            let offset = reader.offset
            let raw = try readInt()
            switch Tag(rawValue: raw) {
            case .fileInfo:
                version = try readInt()
            case .metadata:
                try readClass()
            case .object, .rememberedObject:
                _ = try readObject(remember: raw == Tag.rememberedObject.rawValue)
            case .backReference:
                _ = try readInt()
            case .null:
                continue
            case .end:
                sawEndTag = true
                return
            case nil:
                throw HKTError.unknownTag(raw, offset: offset)
            }
        }
    }

    // MARK: - Primitives

    mutating func readRaw<T>(_ read: (inout BinaryReader) throws -> T) throws -> T {
        do {
            return try read(&reader)
        } catch {
            throw HKTError.truncated(offset: reader.offset)
        }
    }

    mutating func readVarint() throws -> UInt64 {
        let start = reader.offset
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let byte = try readRaw { try $0.readUInt8() }
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return value
            }
            shift += 7
            guard shift < 64 else { throw HKTError.varintTooLong(offset: start) }
        }
    }

    mutating func readInt64() throws -> Int64 {
        let raw = try readVarint()
        let magnitude = Int64(bitPattern: raw >> 1)
        return raw & 1 == 0 ? magnitude : -magnitude
    }

    mutating func readInt() throws -> Int {
        try Int(readInt64())
    }

    mutating func readCount() throws -> Int {
        let offset = reader.offset
        let count = try readInt()
        guard count >= 0, count <= size - reader.offset else {
            throw HKTError.countOutOfRange(count, offset: offset)
        }
        return count
    }

    /// A positive length reads a new string, a negative one names an earlier
    /// string, and zero is the empty string.
    mutating func readString() throws -> String? {
        let offset = reader.offset
        let length = try readInt()
        if length < 0 {
            guard strings.indices.contains(-length) else {
                throw HKTError.badStringReference(length, offset: offset)
            }
            return strings[-length]
        }
        guard length > 0 else { return "" }
        guard length <= size - reader.offset else {
            throw HKTError.countOutOfRange(length, offset: offset)
        }
        let bytes = try readRaw { try $0.read(count: length) }
        // A string that is not UTF-8 keeps its bytes as Latin-1, which never fails.
        let text = String(bytes: bytes, encoding: .utf8)
            ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
        strings.append(text)
        return text
    }

    // MARK: - Class definitions

    mutating func readClass() throws {
        let name = try readString() ?? ""
        let version = try readInt()
        let parentOffset = reader.offset
        let parent = try readInt()
        guard classes.indices.contains(parent) else {
            throw HKTError.badClassIndex(parent, offset: parentOffset)
        }
        let count = try readCount()
        var members: [HKTMember] = []
        for _ in 0 ..< count {
            let memberName = try readString() ?? ""
            try members.append(HKTMember(name: memberName, type: readMemberType()))
        }
        classes.append(HKTClass(
            name: name, version: version, parent: parent == 0 ? nil : parent, members: members
        ))
    }

    mutating func readMemberType() throws -> HKTMemberType {
        let offset = reader.offset
        let word = try readInt()
        guard word >= 0, word & ~0x3F == 0, let base = HKTBaseType(rawValue: word & 0x0F) else {
            throw HKTError.badMemberType(word, offset: offset)
        }
        let tuple = word & 0x20 != 0 ? try readCount() : nil
        let className = base == .object || base == .structure ? try readString() : nil
        return HKTMemberType(
            base: base, isArray: word & 0x10 != 0, tupleCount: tuple, className: className
        )
    }

    func classIndex(named name: String?, offset: Int) throws -> Int {
        guard let name, let index = classes.lastIndex(where: { $0.name == name }) else {
            throw HKTError.unknownStructClass(name ?? "<nil>", offset: offset)
        }
        return index
    }

    func members(ofClass index: Int) -> [HKTMember] {
        var chain: [HKTMember] = []
        var current: Int? = index
        var seen: Set<Int> = []
        while let next = current, next > 0, seen.insert(next).inserted {
            chain = classes[next].members + chain
            current = classes[next].parent
        }
        return chain
    }
}
