// Little helpers the payload codecs share: arrays as raw bytes, optional values,
// and strings. A raw copy keeps every float bit, so a decoded value equals the
// value that was encoded.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public enum CachePayloadError: Error, Equatable, Sendable {
    case truncated
    case badCount(Int)
    case badTag(UInt8)
}

nonisolated public struct CachePayloadWriter: Sendable {
    public private(set) var writer = BinaryWriter()

    public init() {}

    public var data: Data {
        writer.data
    }

    public mutating func array(_ values: [some BitwiseCopyable]) {
        writer.writeUInt32(UInt32(values.count))
        values.withUnsafeBytes { writer.write(Data($0)) }
    }

    public mutating func value(_ value: some BitwiseCopyable) {
        array([value])
    }

    public mutating func int(_ value: Int) {
        writer.writeUInt64(UInt64(bitPattern: Int64(value)))
    }

    public mutating func bool(_ value: Bool) {
        writer.writeUInt8(value ? 1 : 0)
    }

    public mutating func tag(_ value: UInt8) {
        writer.writeUInt8(value)
    }

    public mutating func string(_ value: String?) {
        guard let value else {
            writer.writeUInt8(0)
            return
        }
        writer.writeUInt8(1)
        array(Array(value.utf8))
    }

    public mutating func strings(_ values: [String]) {
        writer.writeUInt32(UInt32(values.count))
        values.forEach { string($0) }
    }
}

nonisolated public struct CachePayloadReader: Sendable {
    private var reader: BinaryReader

    public init(_ data: Data) {
        reader = BinaryReader(data)
    }

    public var isAtEnd: Bool {
        reader.bytesRemaining == 0
    }

    public mutating func array<T: BitwiseCopyable>(_: T.Type = T.self) throws -> [T] {
        let count = try Int(Self.wrap { try reader.readUInt32() })
        let stride = MemoryLayout<T>.stride
        guard count <= reader.bytesRemaining / max(stride, 1) else {
            throw CachePayloadError.badCount(count)
        }
        let bytes = try Self.wrap { try reader.read(count: count * stride) }
        return [T](unsafeUninitializedCapacity: count) { buffer, initialized in
            guard count > 0, let target = buffer.baseAddress else { return }
            bytes.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    UnsafeMutableRawPointer(target).copyMemory(
                        from: base,
                        byteCount: count * stride
                    )
                }
            }
            initialized = count
        }
    }

    public mutating func value<T: BitwiseCopyable>(_: T.Type = T.self) throws -> T {
        let values: [T] = try array()
        guard values.count == 1, let value = values.first else {
            throw CachePayloadError.badCount(values.count)
        }
        return value
    }

    public mutating func int() throws -> Int {
        try Int(Int64(bitPattern: Self.wrap { try reader.readUInt64() }))
    }

    public mutating func bool() throws -> Bool {
        try Self.wrap { try reader.readUInt8() } != 0
    }

    public mutating func tag() throws -> UInt8 {
        try Self.wrap { try reader.readUInt8() }
    }

    public mutating func string() throws -> String? {
        switch try tag() {
        case 0: return nil
        case 1:
            guard let text = try String(bytes: array(UInt8.self), encoding: .utf8) else {
                throw CachePayloadError.truncated
            }
            return text
        case let other: throw CachePayloadError.badTag(other)
        }
    }

    public mutating func strings() throws -> [String] {
        let count = try Int(Self.wrap { try reader.readUInt32() })
        guard count <= reader.bytesRemaining else { throw CachePayloadError.badCount(count) }
        return try (0 ..< count).map { _ in try string() ?? "" }
    }

    private static func wrap<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            throw CachePayloadError.truncated
        }
    }
}
