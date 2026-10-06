// One cache file: a small header that says what the payload was built from and
// with which converter, then the payload. Pure: bytes in, bytes out.
// See docs/engine/asset-cache.md, "Entry layout".

import Foundation
import OpenSkyFormatsCore

nonisolated public enum AssetCacheEntryError: Error, Equatable, Sendable {
    case badMagic
    case unsupportedHeaderVersion(UInt16)
    case unknownKind(UInt8)
    case unknownPreset(UInt8)
    case truncated
}

/// What a payload was built from and how.
nonisolated public struct AssetCacheEntryHeader: Equatable, Sendable {
    public let kind: AssetCacheKind
    public let source: AssetSourceStamp
    public let converterVersion: UInt32
    public let preset: AssetQualityPreset

    public init(
        kind: AssetCacheKind, source: AssetSourceStamp, converterVersion: UInt32,
        preset: AssetQualityPreset
    ) {
        self.kind = kind
        self.source = source
        self.converterVersion = converterVersion
        self.preset = preset
    }
}

nonisolated public enum AssetCacheEntryCodec {
    static let magic = Data("OSAC".utf8)
    static let headerVersion: UInt16 = 1
    /// Payloads start on this boundary, so a mapped payload can feed a Metal buffer.
    static let payloadAlignment = 16

    public static func encode(header: AssetCacheEntryHeader, payload: Data) -> Data {
        var writer = BinaryWriter()
        writer.write(magic)
        writer.writeUInt16(headerVersion)
        writer.writeUInt8(header.kind.rawValue)
        writer.writeUInt8(header.preset.rawValue)
        writer.writeUInt32(header.converterVersion)
        writer.writeUInt64(header.source.size)
        writer.writeUInt64(UInt64(bitPattern: header.source.modified))
        writer.writeUInt64(header.source.contentHash)
        writeText(header.source.origin, to: &writer)
        writeText(header.source.path, to: &writer)
        writer.writeUInt64(UInt64(payload.count))
        let padding = (payloadAlignment - writer.count % payloadAlignment) % payloadAlignment
        writer.write(Data(count: padding))
        writer.write(payload)
        return writer.data
    }

    /// Two 64 KiB texts and the fixed fields fit in this many bytes.
    static let maximumHeaderSize = 4 + 2 + 2 + 4 + 24 + 2 * (2 + 65535) + 8 + payloadAlignment

    /// The header and the payload range. Throws on a file that is not a whole entry.
    public static func decode(_ data: Data) throws -> (AssetCacheEntryHeader, Range<Int>) {
        let prefix = try decodePrefix(data)
        guard prefix.payload.upperBound == data.count else { throw AssetCacheEntryError.truncated }
        let base = data.startIndex
        return (
            prefix.header,
            (base + prefix.payload.lowerBound) ..< (base + prefix.payload.upperBound)
        )
    }

    /// The header and the file size a whole entry has, from the first bytes of a file.
    static func decodeHeader(_ prefix: Data) throws -> (AssetCacheEntryHeader, Int) {
        let decoded = try decodePrefix(prefix)
        return (decoded.header, decoded.payload.upperBound)
    }

    /// The header and the payload's offsets from the start of the file.
    private struct Prefix {
        let header: AssetCacheEntryHeader
        let payload: Range<Int>
    }

    private static func decodePrefix(_ data: Data) throws -> Prefix {
        var reader = BinaryReader(data)
        do {
            guard try reader.read(count: magic.count) == magic else {
                throw AssetCacheEntryError.badMagic
            }
            let version = try reader.readUInt16()
            guard version == headerVersion else {
                throw AssetCacheEntryError.unsupportedHeaderVersion(version)
            }
            let header = try readHeader(&reader)
            let length = try reader.readUInt64()
            let start = (reader.offset + payloadAlignment - 1) / payloadAlignment * payloadAlignment
            guard length <= UInt64(Int.max / 2) else { throw AssetCacheEntryError.truncated }
            return Prefix(header: header, payload: start ..< start + Int(length))
        } catch is BinaryReaderError {
            throw AssetCacheEntryError.truncated
        }
    }

    private static func readHeader(_ reader: inout BinaryReader) throws -> AssetCacheEntryHeader {
        let kindRaw = try reader.readUInt8()
        guard let kind = AssetCacheKind(rawValue: kindRaw) else {
            throw AssetCacheEntryError.unknownKind(kindRaw)
        }
        let presetRaw = try reader.readUInt8()
        guard let preset = AssetQualityPreset(rawValue: presetRaw) else {
            throw AssetCacheEntryError.unknownPreset(presetRaw)
        }
        let converterVersion = try reader.readUInt32()
        let size = try reader.readUInt64()
        let modified = try Int64(bitPattern: reader.readUInt64())
        let hash = try reader.readUInt64()
        let origin = try readText(&reader)
        let path = try readText(&reader)
        let source = AssetSourceStamp(
            origin: origin, path: path, size: size, modified: modified, contentHash: hash
        )
        return AssetCacheEntryHeader(
            kind: kind, source: source, converterVersion: converterVersion, preset: preset
        )
    }

    private static func writeText(_ text: String, to writer: inout BinaryWriter) {
        let bytes = Data(text.utf8.prefix(Int(UInt16.max)))
        writer.writeUInt16(UInt16(bytes.count))
        writer.write(bytes)
    }

    private static func readText(_ reader: inout BinaryReader) throws -> String {
        let count = try Int(reader.readUInt16())
        guard let text = try String(bytes: reader.read(count: count), encoding: .utf8) else {
            throw AssetCacheEntryError.truncated
        }
        return text
    }
}
