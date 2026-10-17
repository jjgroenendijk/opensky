// The write side of `ESSReader`: the save's own types over a little-endian buffer.
// A value the format cannot hold is a typed error, never a silent cut.
// See docs/formats/ess.md#basic-types.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ESSWriter: Sendable {
    private var writer = BinaryWriter()

    /// The largest value a `vsval` holds: 22 bits.
    public static let maximumVSVal: UInt32 = 0x003F_FFFF

    public init() {}

    public var data: Data {
        writer.data
    }

    public var count: Int {
        writer.count
    }

    public mutating func bytes(_ bytes: Data) {
        writer.write(bytes)
    }

    public mutating func uint8(_ value: UInt8) {
        writer.writeUInt8(value)
    }

    public mutating func uint16(_ value: UInt16) {
        writer.writeUInt16(value)
    }

    public mutating func uint32(_ value: UInt32) {
        writer.writeUInt32(value)
    }

    public mutating func uint64(_ value: UInt64) {
        writer.writeUInt64(value)
    }

    public mutating func int8(_ value: Int8) {
        uint8(UInt8(bitPattern: value))
    }

    public mutating func int16(_ value: Int16) {
        uint16(UInt16(bitPattern: value))
    }

    public mutating func int32(_ value: Int32) {
        uint32(UInt32(bitPattern: value))
    }

    public mutating func float32(_ value: Float) {
        writer.writeFloat32(value)
    }

    /// Windows-1252 where the text fits it, as the game writes; UTF-8 otherwise, which
    /// the reader's string policy also decodes.
    public mutating func wstring(_ text: String, _ context: String) throws(ESSError) {
        let encoded = text.data(using: .windowsCP1252) ?? Data(text.utf8)
        guard encoded.count <= Int(UInt16.max) else {
            throw .invalidCount(context: context, count: encoded.count)
        }
        uint16(UInt16(encoded.count))
        bytes(encoded)
    }

    /// The smallest of the three widths that holds `value`.
    public mutating func vsval(_ value: UInt32, _ context: String) throws(ESSError) {
        guard value <= Self.maximumVSVal else {
            throw .invalidCount(context: context, count: Int(value))
        }
        if value < 0x40 {
            uint8(UInt8(value << 2))
        } else if value < 0x4000 {
            uint16(UInt16(value << 2 | 1))
        } else {
            let packed = value << 2 | 2
            uint16(UInt16(packed & 0xFFFF))
            uint8(UInt8(packed >> 16))
        }
    }

    /// A collection count as a `vsval`.
    public mutating func count(_ value: Int, _ context: String) throws(ESSError) {
        guard value >= 0, let narrow = UInt32(exactly: value) else {
            throw .invalidCount(context: context, count: value)
        }
        try vsval(narrow, context)
    }

    /// A collection count as a `uint32`.
    public mutating func count32(_ value: Int, _ context: String) throws(ESSError) {
        guard let narrow = UInt32(exactly: value) else {
            throw .invalidCount(context: context, count: value)
        }
        uint32(narrow)
    }

    /// Three bytes, big endian.
    public mutating func refID(_ ref: ESSRefID) {
        uint8(UInt8(ref.raw >> 16 & 0xFF))
        uint8(UInt8(ref.raw >> 8 & 0xFF))
        uint8(UInt8(ref.raw & 0xFF))
    }

    public mutating func vector3(_ value: SIMD3<Float>) {
        float32(value.x)
        float32(value.y)
        float32(value.z)
    }

    /// Runs `body` on a fresh writer and returns its bytes.
    public static func build(
        _ body: (inout ESSWriter) throws(ESSError) -> Void
    ) throws(ESSError) -> Data {
        var writer = ESSWriter()
        try body(&writer)
        return writer.data
    }
}
