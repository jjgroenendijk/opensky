// CPU decode of a DDS top level to RGBA8, for textures the engine paints on the
// CPU: the chargen face color map (BC1) and the tint masks (24-bit RGB).
// Layout and sources: docs/formats/dds.md, "CPU decode".

import Foundation
import OpenSkyFormatsCore

/// Top mip level as straight RGBA8, row-major from the top-left texel.
nonisolated public struct DecodedImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

nonisolated public enum DDSDecoder {
    /// BC1, BC3, 32-bit RGB, and 24-bit RGB. Other formats throw `unsupported`.
    public static func topLevel(_ data: Data) throws -> DecodedImage {
        if let header = try RGB24Header(data: data) {
            return try header.decode(data)
        }
        let file = try DDSFile(data: data)
        let level = file.mipData(level: 0)
        let width = file.width
        let height = file.height
        let rgba: [UInt8] = switch file.format {
        case .bc1:
            blocks(level, width: width, height: height, stride: 8) { block, out in
                color(block, offset: 0, alwaysFourColors: false, into: &out)
            }
        case .bc3:
            blocks(level, width: width, height: height, stride: 16) { block, out in
                color(block, offset: 8, alwaysFourColors: true, into: &out)
                alpha(block, into: &out)
            }
        case .rgba8888: Array(level)
        case .bgra8888, .xrgb8888: swizzleBGRA(level, opaque: file.format == .xrgb8888)
        default: throw DDSError.unsupported("CPU decode of \(file.format)")
        }
        return DecodedImage(width: width, height: height, rgba: rgba)
    }

    /// Walks the 4x4 blocks; `decode` fills 16 RGBA texels for one block.
    private static func blocks(
        _ level: Data, width: Int, height: Int, stride: Int,
        decode: (ArraySlice<UInt8>, inout [UInt8]) -> Void
    ) -> [UInt8] {
        let bytes = [UInt8](level)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let across = (width + 3) / 4
        var texels = [UInt8](repeating: 0, count: 64)
        for blockY in 0 ..< (height + 3) / 4 {
            for blockX in 0 ..< across {
                let start = (blockY * across + blockX) * stride
                guard start + stride <= bytes.count else { return rgba }
                decode(bytes[start ..< start + stride], &texels)
                for row in 0 ..< 4 where blockY * 4 + row < height {
                    for column in 0 ..< 4 where blockX * 4 + column < width {
                        let target = ((blockY * 4 + row) * width + blockX * 4 + column) * 4
                        let source = (row * 4 + column) * 4
                        rgba[target ..< target + 4] = texels[source ..< source + 4]
                    }
                }
            }
        }
        return rgba
    }

    private static func word(_ block: ArraySlice<UInt8>, _ offset: Int) -> UInt16 {
        let base = block.startIndex + offset
        return UInt16(block[base]) | UInt16(block[base + 1]) << 8
    }

    private static func expand(_ value: UInt16) -> SIMD3<Int> {
        let red = Int(value >> 11 & 0x1F)
        let green = Int(value >> 5 & 0x3F)
        let blue = Int(value & 0x1F)
        return SIMD3(red << 3 | red >> 2, green << 2 | green >> 4, blue << 3 | blue >> 2)
    }

    /// The BC1 color block at `offset`; BC3 always uses the four-color mode.
    private static func color(
        _ block: ArraySlice<UInt8>, offset: Int, alwaysFourColors: Bool, into out: inout [UInt8]
    ) {
        let first = word(block, offset)
        let second = word(block, offset + 2)
        let low = expand(first)
        let high = expand(second)
        let fourColors = alwaysFourColors || first > second
        let palette: [SIMD4<Int>] = fourColors
            ? [
                SIMD4(low, 255), SIMD4(high, 255),
                SIMD4((low &* 2 &+ high) / 3, 255), SIMD4((low &+ high &* 2) / 3, 255)
            ]
            : [SIMD4(low, 255), SIMD4(high, 255), SIMD4((low &+ high) / 2, 255), .zero]
        let base = block.startIndex + offset + 4
        for texel in 0 ..< 16 {
            let index = Int(block[base + texel / 4] >> UInt8(texel % 4 * 2) & 0x3)
            let entry = palette[index]
            for channel in 0 ..< 4 {
                out[texel * 4 + channel] = UInt8(entry[channel])
            }
        }
    }

    /// The BC3 alpha block: two end points and sixteen 3-bit indices.
    private static func alpha(_ block: ArraySlice<UInt8>, into out: inout [UInt8]) {
        let base = block.startIndex
        let first = Int(block[base])
        let second = Int(block[base + 1])
        var bits: UInt64 = 0
        for byte in 0 ..< 6 {
            bits |= UInt64(block[base + 2 + byte]) << UInt64(byte * 8)
        }
        for texel in 0 ..< 16 {
            let index = Int(bits >> UInt64(texel * 3) & 0x7)
            out[texel * 4 + 3] = UInt8(alphaValue(index, first, second))
        }
    }

    private static func alphaValue(_ index: Int, _ first: Int, _ second: Int) -> Int {
        switch index {
        case 0: return first
        case 1: return second
        default: break
        }
        if first > second {
            return ((8 - index) * first + (index - 1) * second) / 7
        }
        switch index {
        case 6: return 0
        case 7: return 255
        default: return ((6 - index) * first + (index - 1) * second) / 5
        }
    }

    private static func swizzleBGRA(_ level: Data, opaque: Bool) -> [UInt8] {
        var bytes = [UInt8](level)
        for texel in stride(from: 0, to: bytes.count - 3, by: 4) {
            bytes.swapAt(texel, texel + 2)
            if opaque {
                bytes[texel + 3] = 255
            }
        }
        return bytes
    }
}

/// The legacy 24-bit `DDPF_RGB` layout that `DDSFile` does not read; the tint
/// masks use it. Nil for any other header.
nonisolated private struct RGB24Header {
    let width: Int
    let height: Int
    let pitch: Int
    /// Byte position of red, green, and blue inside one 3-byte texel.
    let channels: SIMD3<Int>

    init?(data: Data) throws {
        var reader = BinaryReader(data)
        guard data.count >= 128, try reader.readFourCC() == "DDS " else { return nil }
        reader = BinaryReader(data, offset: 8)
        let flags = try reader.readUInt32()
        let height = try Int(reader.readUInt32())
        let width = try Int(reader.readUInt32())
        let pitch = try Int(reader.readUInt32())
        reader = BinaryReader(data, offset: 80)
        let formatFlags = try reader.readUInt32()
        _ = try reader.readUInt32()
        let bitCount = try reader.readUInt32()
        let masks = try [reader.readUInt32(), reader.readUInt32(), reader.readUInt32()]
        guard formatFlags & 0x4 == 0, formatFlags & 0x40 != 0, bitCount == 24 else { return nil }
        let positions = masks.map { [0x0000FF, 0x00FF00, 0xFF0000].firstIndex(of: $0) }
        guard let red = positions[0], let green = positions[1], let blue = positions[2] else {
            throw DDSError.unsupported("24-bit RGB channel masks")
        }
        guard width > 0, height > 0, width <= 16384, height <= 16384 else {
            throw DDSError.malformed("24-bit RGB size \(width)x\(height)")
        }
        self.width = width
        self.height = height
        self.pitch = flags & 0x8 != 0 && pitch >= width * 3 ? pitch : width * 3
        channels = SIMD3(red, green, blue)
    }

    func decode(_ data: Data) throws -> DecodedImage {
        let bytes = [UInt8](data)
        guard 128 + pitch * (height - 1) + width * 3 <= bytes.count else {
            throw DDSError.malformed("24-bit RGB payload shorter than \(width)x\(height)")
        }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let source = 128 + row * pitch + column * 3
                let target = (row * width + column) * 4
                for channel in 0 ..< 3 {
                    rgba[target + channel] = bytes[source + channels[channel]]
                }
            }
        }
        return DecodedImage(width: width, height: height, rgba: rgba)
    }
}
