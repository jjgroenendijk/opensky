// Synthetic SWF container builder for parser tests. Fixtures are assembled
// byte-by-byte in code — never extracted game files (AGENTS.md "Legal & IP
// boundary"). Compressed bodies reuse ESMFixture.zlibStream.
//
// Reference: Adobe SWF File Format Specification, version 19.

import Foundation

/// Builds a minimal spec-conformant SWF (FWS or CWS) byte blob.
struct SWFFixture {
    struct Tag {
        let code: UInt16
        let body: Data
    }

    var signature = "FWS"
    var version: UInt8 = 6
    var xMin: Int32 = 0
    var xMax: Int32 = 8000
    var yMin: Int32 = 0
    var yMax: Int32 = 6000
    /// FrameRate as 8.8 fixed point (integer fps << 8). 24 fps default.
    var frameRateFixed: UInt16 = 24 << 8
    var frameCount: UInt16 = 1
    var tags: [Tag] = []
    /// Append the terminating End tag (code 0, empty body) after `tags`.
    var appendEnd = true

    func build() -> Data {
        var body = rectBytes()
        body.appendUInt16(frameRateFixed)
        body.appendUInt16(frameCount)
        for tag in tags {
            body.append(Self.tagBytes(code: tag.code, body: tag.body))
        }
        if appendEnd {
            body.append(Self.tagBytes(code: 0, body: Data()))
        }

        var out = Data(signature.utf8)
        out.append(version)
        // FileLength is the uncompressed total including this 8-byte header.
        out.appendUInt32(UInt32(8 + body.count))
        out.append(signature == "CWS" ? ESMFixture.zlibStream(body) : body)
        return out
    }

    /// FrameSize RECT: UB[5] Nbits, then Xmin/Xmax/Ymin/Ymax as SB[Nbits],
    /// MSB-first, padded to a byte boundary.
    private func rectBytes() -> Data {
        let nbits = [xMin, xMax, yMin, yMax].map(Self.signedBitWidth).max() ?? 1
        var writer = BitWriter()
        writer.writeUB(UInt32(nbits), count: 5)
        for value in [xMin, xMax, yMin, yMax] {
            writer.writeSB(value, count: nbits)
        }
        return writer.bytes()
    }

    /// RECORDHEADER + body. Long form (UI32 length) when body >= 0x3F bytes.
    static func tagBytes(code: UInt16, body: Data) -> Data {
        var out = Data()
        if body.count >= 0x3F {
            out.appendUInt16((code << 6) | 0x3F)
            out.appendUInt32(UInt32(body.count))
        } else {
            out.appendUInt16((code << 6) | UInt16(body.count))
        }
        out.append(body)
        return out
    }

    /// Minimum SB width holding `value` in two's complement (>= 1).
    static func signedBitWidth(_ value: Int32) -> Int {
        var bits = 1
        while value < -(Int32(1) << (bits - 1)) || value > (Int32(1) << (bits - 1)) - 1 {
            bits += 1
        }
        return bits
    }
}

/// MSB-first bit accumulator mirroring SWFBitReader's read order.
private struct BitWriter {
    private var bits: [UInt8] = []

    mutating func writeUB(_ value: UInt32, count: Int) {
        for index in stride(from: count - 1, through: 0, by: -1) {
            bits.append(UInt8((value >> index) & 1))
        }
    }

    mutating func writeSB(_ value: Int32, count: Int) {
        let mask: UInt32 = count >= 32 ? .max : (1 << count) - 1
        writeUB(UInt32(bitPattern: value) & mask, count: count)
    }

    func bytes() -> Data {
        var out = Data()
        var accumulator: UInt8 = 0
        var filled = 0
        for bit in bits {
            accumulator = (accumulator << 1) | bit
            filled += 1
            if filled == 8 {
                out.append(accumulator)
                accumulator = 0
                filled = 0
            }
        }
        if filled > 0 {
            out.append(accumulator << (8 - filled))
        }
        return out
    }
}
