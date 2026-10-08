// Bounds-checked little-endian reader over raw bytes. Every format parser
// (BSA, ESM, NIF) reads through this so malformed input throws instead of
// crashing (AGENTS.md "Reverse-engineering discipline").

import Foundation

nonisolated public enum BinaryReaderError: Error, Equatable, Sendable {
    /// Read past the end: wanted `count` bytes at `offset`, only `available` left.
    case outOfBounds(offset: Int, count: Int, available: Int)
    /// Null terminator not found scanning a zero-terminated string.
    case unterminatedString(offset: Int)
    /// Bytes are not decodable text in the expected encoding. Only `.strict`
    /// decoding raises this; `.gameText` always yields a string.
    case invalidString(offset: Int)
}

/// Sequential cursor over a `Data`. Value type: copy to branch, cheap slices.
nonisolated public struct BinaryReader: Sendable {
    public let data: Data
    public private(set) var offset: Int

    public init(_ data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    public var bytesRemaining: Int {
        max(0, data.count - offset)
    }

    public mutating func seek(to newOffset: Int) {
        offset = newOffset
    }

    public mutating func skip(_ count: Int) {
        offset += count
    }

    public mutating func read(count: Int) throws -> Data {
        try requireBytes(count)
        // Data slices keep the parent's indices; rebase via subdata for safety.
        let slice = data
            .subdata(in: (data.startIndex + offset) ..< (data.startIndex + offset + count))
        offset += count
        return slice
    }

    public mutating func readUInt8() throws -> UInt8 {
        try requireBytes(1)
        let value = data[data.startIndex + offset]
        offset += 1
        return value
    }

    public mutating func readUInt16() throws -> UInt16 {
        try readInteger()
    }

    public mutating func readUInt32() throws -> UInt32 {
        try readInteger()
    }

    public mutating func readUInt64() throws -> UInt64 {
        try readInteger()
    }

    /// IEEE 754 single-precision float, little-endian bit pattern.
    public mutating func readFloat32() throws -> Float {
        try Float(bitPattern: readUInt32())
    }

    /// `count` little-endian integers in one bounds check, for index and vertex arrays.
    public mutating func readIntegers<T: FixedWidthInteger>(
        _: T.Type = T.self,
        count: Int
    ) throws -> [T] {
        let size = MemoryLayout<T>.size
        guard count >= 0, count <= Int.max / size else {
            throw BinaryReaderError.outOfBounds(
                offset: offset,
                count: count,
                available: bytesRemaining
            )
        }
        try requireBytes(count * size)
        let start = offset
        offset += count * size
        return data.withUnsafeBytes { raw in
            (0 ..< count).map { index in
                let offset = start + index * size
                return T(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: T.self))
            }
        }
    }

    /// `count` little-endian floats in one bounds check.
    public mutating func readFloat32s(count: Int) throws -> [Float] {
        try readIntegers(UInt32.self, count: count).map(Float.init(bitPattern:))
    }

    /// Loads straight from the buffer: a `Data` per scalar dominated NIF parsing.
    private mutating func readInteger<T: FixedWidthInteger>() throws -> T {
        let size = MemoryLayout<T>.size
        try requireBytes(size)
        let start = offset
        offset += size
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: start, as: T.self) }
        return T(littleEndian: value)
    }

    private func requireBytes(_ count: Int) throws {
        guard count >= 0, offset >= 0, count <= data.count - offset else {
            throw BinaryReaderError.outOfBounds(
                offset: offset,
                count: count,
                available: bytesRemaining
            )
        }
    }

    /// Raw bytes of a zero-terminated string, terminator excluded. Cursor ends
    /// past the terminator. For callers that pick the text encoding themselves.
    public mutating func readZStringData() throws -> Data {
        let start = offset
        var end = offset
        while true {
            guard end < data.count else {
                throw BinaryReaderError.unterminatedString(offset: start)
            }
            if data[data.startIndex + end] == 0 {
                break
            }
            end += 1
        }
        let bytes = try read(count: end - start)
        skip(1) // terminator
        return bytes
    }

    /// Zero-terminated string ("zstring"). Cursor ends past the terminator.
    /// Decodes under the engine-wide game-text policy unless told otherwise
    /// (`GameText`, docs/decisions/string-decoding.md).
    public mutating func readZString(_ decoding: TextDecoding = .gameText) throws -> String {
        let start = offset
        let bytes = try readZStringData()
        guard let string = decoding.decode(bytes) else {
            throw BinaryReaderError.invalidString(offset: start)
        }
        return string
    }

    /// Length-prefixed string including a trailing null ("bzstring", BSA folder names).
    public mutating func readBZString(_ decoding: TextDecoding = .gameText) throws -> String {
        let start = offset
        let length = try Int(readUInt8())
        guard length > 0 else { return "" }
        let bytes = try read(count: length - 1)
        skip(1) // terminator counted in the length prefix
        guard let string = decoding.decode(bytes) else {
            throw BinaryReaderError.invalidString(offset: start)
        }
        return string
    }

    /// Length-prefixed string without terminator ("bstring", embedded file names).
    public mutating func readBString(_ decoding: TextDecoding = .gameText) throws -> String {
        let start = offset
        let length = try Int(readUInt8())
        let bytes = try read(count: length)
        guard let string = decoding.decode(bytes) else {
            throw BinaryReaderError.invalidString(offset: start)
        }
        return string
    }
}
