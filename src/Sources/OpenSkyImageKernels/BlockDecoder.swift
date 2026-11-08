// BC1 and BC3 block decode to RGBA8. Block layouts: docs/formats/dds.md, "CPU decode".

nonisolated public enum BlockDecoder {
    public static func bc1(_ bytes: [UInt8], width: Int, height: Int) -> [UInt8] {
        blocks(bytes, width: width, height: height, stride: 8) { block, out in
            color(block, offset: 0, alwaysFourColors: false, into: &out)
        }
    }

    /// BC3 color blocks always use the four-color mode.
    public static func bc3(_ bytes: [UInt8], width: Int, height: Int) -> [UInt8] {
        blocks(bytes, width: width, height: height, stride: 16) { block, out in
            color(block, offset: 8, alwaysFourColors: true, into: &out)
            alpha(block, into: &out)
        }
    }

    /// Walks the 4x4 blocks; `decode` fills 16 RGBA texels for one block.
    private static func blocks(
        _ bytes: [UInt8], width: Int, height: Int, stride: Int,
        decode: (ArraySlice<UInt8>, inout [UInt8]) -> Void
    ) -> [UInt8] {
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

    /// Swaps blue and red; `opaque` also sets alpha, for the X8 formats.
    public static func swizzleBGRA(_ source: [UInt8], opaque: Bool) -> [UInt8] {
        var bytes = source
        for texel in stride(from: 0, to: bytes.count - 3, by: 4) {
            bytes.swapAt(texel, texel + 2)
            if opaque {
                bytes[texel + 3] = 255
            }
        }
        return bytes
    }
}
