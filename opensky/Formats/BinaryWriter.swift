// Deterministic little-endian writer over raw bytes. The write-side counterpart
// to BinaryReader, used by native save/container formats that must round-trip
// byte-for-byte (AGENTS.md "Reverse-engineering discipline").

import Foundation

nonisolated enum BinaryWriterError: Error, Equatable {
    /// The string could not be represented in the requested encoding.
    case unencodableString(String)
    /// A zero-terminated string cannot contain an embedded NUL byte.
    case embeddedNull(String)
}

/// Append-only byte buffer builder. Value type: copy to branch, cheap to extend.
nonisolated struct BinaryWriter {
    private(set) var data = Data()

    var count: Int {
        data.count
    }

    mutating func write(_ bytes: Data) {
        data.append(bytes)
    }

    mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
    }

    mutating func writeUInt16(_ value: UInt16) {
        writeInteger(value)
    }

    mutating func writeUInt32(_ value: UInt32) {
        writeInteger(value)
    }

    mutating func writeUInt64(_ value: UInt64) {
        writeInteger(value)
    }

    /// IEEE 754 single-precision float, little-endian bit pattern.
    mutating func writeFloat32(_ value: Float) {
        writeUInt32(value.bitPattern)
    }

    private mutating func writeInteger(_ value: some FixedWidthInteger) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    /// Zero-terminated string ("zstring"): encoded bytes plus a NUL terminator.
    mutating func writeZString(
        _ string: String,
        encoding: String.Encoding = .windowsCP1252
    ) throws {
        guard !string.contains("\0") else {
            throw BinaryWriterError.embeddedNull(string)
        }
        guard let bytes = string.data(using: encoding) else {
            throw BinaryWriterError.unencodableString(string)
        }
        data.append(bytes)
        data.append(0)
    }
}
