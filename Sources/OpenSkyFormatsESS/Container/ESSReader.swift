// A cursor over save bytes with the save's own types: `wstring`, `vsval`, and the
// three-byte ref id. Every read failure becomes `ESSError.truncated` naming the
// structure. See docs/formats/ess.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ESSReader: Sendable {
    private var reader: BinaryReader

    public init(_ data: Data) {
        reader = BinaryReader(data)
    }

    public var offset: Int {
        reader.offset
    }

    public var bytesRemaining: Int {
        reader.bytesRemaining
    }

    public var isAtEnd: Bool {
        reader.bytesRemaining == 0
    }

    public mutating func seek(to offset: Int) {
        reader.seek(to: offset)
    }

    public mutating func bytes(_ count: Int, _ context: String) throws(ESSError) -> Data {
        guard count >= 0, count <= reader.bytesRemaining else {
            throw .truncated(context: context)
        }
        do {
            return try reader.read(count: count)
        } catch {
            throw .truncated(context: context)
        }
    }

    public mutating func skip(_ count: Int, _ context: String) throws(ESSError) {
        guard count >= 0, count <= reader.bytesRemaining else {
            throw .truncated(context: context)
        }
        reader.skip(count)
    }

    public mutating func uint8(_ context: String) throws(ESSError) -> UInt8 {
        do { return try reader.readUInt8() } catch { throw .truncated(context: context) }
    }

    public mutating func uint16(_ context: String) throws(ESSError) -> UInt16 {
        do { return try reader.readUInt16() } catch { throw .truncated(context: context) }
    }

    public mutating func uint32(_ context: String) throws(ESSError) -> UInt32 {
        do { return try reader.readUInt32() } catch { throw .truncated(context: context) }
    }

    public mutating func uint64(_ context: String) throws(ESSError) -> UInt64 {
        do { return try reader.readUInt64() } catch { throw .truncated(context: context) }
    }

    public mutating func int8(_ context: String) throws(ESSError) -> Int8 {
        try Int8(bitPattern: uint8(context))
    }

    public mutating func int16(_ context: String) throws(ESSError) -> Int16 {
        try Int16(bitPattern: uint16(context))
    }

    public mutating func int32(_ context: String) throws(ESSError) -> Int32 {
        try Int32(bitPattern: uint32(context))
    }

    public mutating func float32(_ context: String) throws(ESSError) -> Float {
        try Float(bitPattern: uint32(context))
    }

    /// A `uint16` length and that many Windows-1252 bytes, not zero terminated.
    public mutating func wstring(_ context: String) throws(ESSError) -> String {
        let length = try Int(uint16(context))
        let raw = try bytes(length, context)
        return GameText.decode(raw)
    }

    /// The low two bits of the first byte give the width (1, 2, or 4 bytes, little
    /// endian); the value is the rest of the bits.
    public mutating func vsval(_ context: String) throws(ESSError) -> UInt32 {
        let first = try uint8(context)
        switch first & 0b11 {
        case 0:
            return UInt32(first) >> 2
        case 1:
            let second = try uint8(context)
            return (UInt32(first) | UInt32(second) << 8) >> 2
        case 2:
            let second = try uint16(context)
            return (UInt32(first) | UInt32(second) << 8) >> 2
        default:
            throw .invalidValue(context: "\(context) vsval width bits are 3")
        }
    }

    /// A `vsval` count checked against the bytes left, given the smallest size of
    /// one element, so a corrupt count never reserves memory.
    public mutating func count(
        _ context: String, minimumElementSize: Int = 1
    ) throws(ESSError) -> Int {
        try checked(Int(vsval(context)), context, minimumElementSize: minimumElementSize)
    }

    /// A `uint32` count checked like `count(_:minimumElementSize:)`.
    public mutating func count32(
        _ context: String, minimumElementSize: Int = 1
    ) throws(ESSError) -> Int {
        try checked(Int(uint32(context)), context, minimumElementSize: minimumElementSize)
    }

    private func checked(
        _ count: Int, _ context: String, minimumElementSize: Int
    ) throws(ESSError) -> Int {
        guard count * max(0, minimumElementSize) <= reader.bytesRemaining else {
            throw .invalidCount(context: context, count: count)
        }
        return count
    }

    public mutating func refID(_ context: String) throws(ESSError) -> ESSRefID {
        let raw = try bytes(3, context)
        let value = raw.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return ESSRefID(raw: value)
    }

    public mutating func vector3(_ context: String) throws(ESSError) -> SIMD3<Float> {
        try SIMD3(float32(context), float32(context), float32(context))
    }
}
