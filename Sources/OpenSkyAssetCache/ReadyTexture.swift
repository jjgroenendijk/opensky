// A texture as the GPU takes it: a pixel format, and the bytes and row stride of
// every mip level. The extract converter stores the shipped DDS blocks as they
// are; the ASTC converter stores re-encoded blocks in the same shape.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh

nonisolated public enum ReadyTextureFormat: UInt8, Sendable, CaseIterable {
    case bc1 = 1, bc2, bc3, bc4, bc5, bc7
    case rgba8 = 10, bgra8
    case astc4x4 = 20, astc6x6, astc8x8, astc5x5

    public init(_ format: DDSPixelFormat) {
        switch format {
        case .bc1: self = .bc1
        case .bc2: self = .bc2
        case .bc3: self = .bc3
        case .bc4: self = .bc4
        case .bc5: self = .bc5
        case .bc7: self = .bc7
        case .rgba8888: self = .rgba8
        case .bgra8888, .xrgb8888: self = .bgra8
        }
    }

    /// Texels per block edge.
    public var blockDimension: Int {
        switch self {
        case .rgba8, .bgra8: 1
        case .bc1, .bc2, .bc3, .bc4, .bc5, .bc7, .astc4x4: 4
        case .astc5x5: 5
        case .astc6x6: 6
        case .astc8x8: 8
        }
    }

    /// Bits of GPU memory per texel: 4 for BC1, 8 for BC3 and ASTC 4x4, 2 for ASTC 8x8.
    public var bitsPerPixel: Double {
        Double(bytesPerBlock * 8) / Double(blockDimension * blockDimension)
    }

    /// `3.56` for ASTC 6x6, `8` for BC3.
    public var bitsPerPixelText: String {
        let value = bitsPerPixel
        return value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    /// `BC1`, `ASTC 6x6`.
    public var title: String {
        switch self {
        case .bc1: "BC1"
        case .bc2: "BC2"
        case .bc3: "BC3"
        case .bc4: "BC4"
        case .bc5: "BC5"
        case .bc7: "BC7"
        case .rgba8: "RGBA8"
        case .bgra8: "BGRA8"
        case .astc4x4, .astc5x5, .astc6x6, .astc8x8: "ASTC \(blockDimension)x\(blockDimension)"
        }
    }

    public var bytesPerBlock: Int {
        switch self {
        case .bc1, .bc4: 8
        case .rgba8, .bgra8: 4
        default: 16
        }
    }

    public var isASTC: Bool {
        rawValue >= Self.astc4x4.rawValue
    }

    public func bytesPerRow(width: Int) -> Int {
        (width + blockDimension - 1) / blockDimension * bytesPerBlock
    }

    public func byteCount(width: Int, height: Int) -> Int {
        bytesPerRow(width: width) * ((height + blockDimension - 1) / blockDimension)
    }
}

nonisolated public struct ReadyTexture: Equatable, Sendable {
    public let format: ReadyTextureFormat
    public let width: Int
    public let height: Int
    public let mipCount: Int
    /// Every level, largest first, packed with no gaps.
    public let bytes: Data

    public init(format: ReadyTextureFormat, width: Int, height: Int, mipCount: Int, bytes: Data) {
        self.format = format
        self.width = width
        self.height = height
        self.mipCount = mipCount
        self.bytes = bytes
    }

    public func width(level: Int) -> Int {
        max(1, width >> level)
    }

    public func height(level: Int) -> Int {
        max(1, height >> level)
    }

    public func bytesPerRow(level: Int) -> Int {
        format.bytesPerRow(width: width(level: level))
    }

    /// Offsets into `bytes`, relative to its start index.
    public func levelRange(_ level: Int) -> Range<Int> {
        var offset = 0
        for earlier in 0 ..< level {
            offset += format.byteCount(width: width(level: earlier), height: height(level: earlier))
        }
        return offset ..< offset + format.byteCount(
            width: width(level: level),
            height: height(level: level)
        )
    }

    public var expectedByteCount: Int {
        levelRange(mipCount - 1).upperBound
    }

    /// The levels from the first one no larger than `side` on its long side, as they
    /// are: the smaller levels are already in the source, so nothing is lost.
    public func keepingLevels(fittingWithin side: Int?) -> ReadyTexture {
        guard let side else { return self }
        var first = 0
        while first < mipCount - 1, max(width(level: first), height(level: first)) > side {
            first += 1
        }
        guard first > 0 else { return self }
        let start = bytes.startIndex + levelRange(first).lowerBound
        return ReadyTexture(
            format: format, width: width(level: first), height: height(level: first),
            mipCount: mipCount - first, bytes: bytes[start ..< bytes.endIndex]
        )
    }

    /// The shipped levels as they are. `xrgb8888` gets an opaque alpha byte,
    /// as the direct upload does, because X is undefined.
    public init(dds: DDSFile) {
        var bytes = Data()
        for level in 0 ..< dds.mipCount {
            let level = dds.mipData(level: level)
            bytes.append(dds.format == .xrgb8888 ? Self.withOpaqueAlpha(level) : level)
        }
        self.init(
            format: ReadyTextureFormat(dds.format), width: dds.width, height: dds.height,
            mipCount: dds.mipCount, bytes: bytes
        )
    }

    static func withOpaqueAlpha(_ source: Data) -> Data {
        var result = Data(source)
        for offset in stride(from: 3, to: result.count, by: 4) {
            result[offset] = 255
        }
        return result
    }
}

nonisolated public enum ReadyTextureError: Error, Equatable, Sendable {
    case unknownFormat(UInt8)
    case badSize(width: Int, height: Int, mipCount: Int)
    case byteCountMismatch(expected: Int, actual: Int)
}

/// The texture payload: format, width, height, mip count, then the level bytes.
nonisolated public enum ReadyTextureCodec {
    public static let headerSize = 16

    public static func encode(_ texture: ReadyTexture) -> Data {
        var writer = BinaryWriter()
        writer.writeUInt8(texture.format.rawValue)
        writer.write(Data(count: 3))
        writer.writeUInt32(UInt32(texture.width))
        writer.writeUInt32(UInt32(texture.height))
        writer.writeUInt32(UInt32(texture.mipCount))
        writer.write(texture.bytes)
        return writer.data
    }

    /// The level bytes stay a slice of `payload`, so a mapped file is not copied.
    public static func decode(_ payload: Data) throws -> ReadyTexture {
        var reader = BinaryReader(payload)
        do {
            let raw = try reader.readUInt8()
            guard let format = ReadyTextureFormat(rawValue: raw) else {
                throw ReadyTextureError.unknownFormat(raw)
            }
            reader.skip(3)
            let width = try Int(reader.readUInt32())
            let height = try Int(reader.readUInt32())
            let mipCount = try Int(reader.readUInt32())
            guard
                (1 ... 16384).contains(width), (1 ... 16384).contains(height),
                (1 ... 15).contains(mipCount)
            else {
                throw ReadyTextureError
                    .badSize(width: width, height: height, mipCount: mipCount)
            }
            let start = payload.startIndex + headerSize
            let texture = ReadyTexture(
                format: format, width: width, height: height, mipCount: mipCount,
                bytes: payload[start ..< payload.endIndex]
            )
            guard texture.expectedByteCount == texture.bytes.count else {
                throw ReadyTextureError.byteCountMismatch(
                    expected: texture.expectedByteCount, actual: texture.bytes.count
                )
            }
            return texture
        } catch is BinaryReaderError {
            throw CachePayloadError.truncated
        }
    }
}
