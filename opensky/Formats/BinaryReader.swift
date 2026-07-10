// Bounds-checked little-endian reader over raw bytes. Every format parser
// (BSA, ESM, NIF) reads through this so malformed input throws instead of
// crashing (AGENTS.md "Reverse-engineering discipline").

import Foundation

nonisolated enum BinaryReaderError: Error, Equatable {
    /// Read past the end: wanted `count` bytes at `offset`, only `available` left.
    case outOfBounds(offset: Int, count: Int, available: Int)
    /// Null terminator not found scanning a zero-terminated string.
    case unterminatedString(offset: Int)
    /// Bytes are not decodable text in the expected encoding.
    case invalidString(offset: Int)
}

/// Sequential cursor over a `Data`. Value type: copy to branch, cheap slices.
nonisolated struct BinaryReader {
    let data: Data
    private(set) var offset: Int

    init(_ data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    var bytesRemaining: Int {
        max(0, data.count - offset)
    }

    mutating func seek(to newOffset: Int) {
        offset = newOffset
    }

    mutating func skip(_ count: Int) {
        offset += count
    }

    mutating func read(count: Int) throws -> Data {
        guard count >= 0, offset >= 0, offset + count <= data.count else {
            throw BinaryReaderError.outOfBounds(
                offset: offset,
                count: count,
                available: bytesRemaining
            )
        }
        // Data slices keep the parent's indices; rebase via subdata for safety.
        let slice = data
            .subdata(in: (data.startIndex + offset) ..< (data.startIndex + offset + count))
        offset += count
        return slice
    }

    mutating func readUInt8() throws -> UInt8 {
        try read(count: 1)[0]
    }

    mutating func readUInt16() throws -> UInt16 {
        try readInteger()
    }

    mutating func readUInt32() throws -> UInt32 {
        try readInteger()
    }

    mutating func readUInt64() throws -> UInt64 {
        try readInteger()
    }

    /// IEEE 754 single-precision float, little-endian bit pattern.
    mutating func readFloat32() throws -> Float {
        try Float(bitPattern: readUInt32())
    }

    private mutating func readInteger<T: FixedWidthInteger>() throws -> T {
        let bytes = try read(count: MemoryLayout<T>.size)
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: bytes) }
        return T(littleEndian: value)
    }

    /// Raw bytes of a zero-terminated string, terminator excluded. Cursor ends
    /// past the terminator. For callers that pick the text encoding themselves.
    mutating func readZStringData() throws -> Data {
        let start = offset
        var end = offset
        while true {
            guard end < data.count else {
                throw BinaryReaderError.unterminatedString(offset: start)
            }
            if data[data.startIndex + end] == 0 { break }
            end += 1
        }
        let bytes = try read(count: end - start)
        skip(1) // terminator
        return bytes
    }

    /// Zero-terminated string ("zstring"). Cursor ends past the terminator.
    mutating func readZString(encoding: String.Encoding = .windowsCP1252) throws -> String {
        let start = offset
        let bytes = try readZStringData()
        guard let string = String(data: bytes, encoding: encoding) else {
            throw BinaryReaderError.invalidString(offset: start)
        }
        return string
    }

    /// Length-prefixed string including a trailing null ("bzstring", BSA folder names).
    mutating func readBZString(encoding: String.Encoding = .windowsCP1252) throws -> String {
        let start = offset
        let length = try Int(readUInt8())
        guard length > 0 else { return "" }
        let bytes = try read(count: length - 1)
        skip(1) // terminator counted in the length prefix
        guard let string = String(data: bytes, encoding: encoding) else {
            throw BinaryReaderError.invalidString(offset: start)
        }
        return string
    }

    /// Length-prefixed string without terminator ("bstring", embedded file names).
    mutating func readBString(encoding: String.Encoding = .windowsCP1252) throws -> String {
        let start = offset
        let length = try Int(readUInt8())
        let bytes = try read(count: length)
        guard let string = String(data: bytes, encoding: encoding) else {
            throw BinaryReaderError.invalidString(offset: start)
        }
        return string
    }
}
