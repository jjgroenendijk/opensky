// Unit tests for the clean-room LZ4 decoder. Byte vectors hand-assembled
// from the public block/frame specs (see LZ4.swift references).

import Foundation
@testable import opensky
import Testing

struct LZ4Tests {
    /// token 0x44: 4 literals, match length 4+4=8; offset 4 -> repeats "abcd";
    /// final sequence is literals-only "XYZQW".
    private static let sampleBlock = Data([0x44]) + Data("abcd".utf8)
        + Data([0x04, 0x00, 0x50]) + Data("XYZQW".utf8)
    private static let samplePlain = Data("abcdabcdabcdXYZQW".utf8)

    private static func frame(blocks: [(Data, uncompressed: Bool)]) -> Data {
        var out = Data([0x04, 0x22, 0x4D, 0x18]) // magic, little-endian
        out.append(contentsOf: [0x40, 0x40, 0x00]) // FLG v01, BD 64K, HC (unchecked)
        for (block, uncompressed) in blocks {
            var size = UInt32(block.count)
            if uncompressed {
                size |= 0x8000_0000
            }
            withUnsafeBytes(of: size.littleEndian) { out.append(contentsOf: $0) }
            out.append(block)
        }
        out.append(contentsOf: [0, 0, 0, 0]) // EndMark
        return out
    }

    @Test func decodesBlockWithOverlapAndLiterals() throws {
        var output: [UInt8] = []
        try LZ4.decompressBlock(Self.sampleBlock, into: &output, sizeLimit: 64)
        #expect(Data(output) == Self.samplePlain)
    }

    @Test func decodesRLEOverlap() throws {
        // 1 literal "a", match offset 1 length 8 -> "a" * 9.
        let block = Data([0x14, 0x61, 0x01, 0x00, 0x10, 0x62])
        var output: [UInt8] = []
        try LZ4.decompressBlock(block, into: &output, sizeLimit: 64)
        #expect(Data(output) == Data("aaaaaaaaab".utf8))
    }

    @Test func decodesFrameWithCompressedBlock() throws {
        let frame = Self.frame(blocks: [(Self.sampleBlock, uncompressed: false)])
        let plain = try LZ4.decompressFrame(frame, sizeLimit: Self.samplePlain.count)
        #expect(plain == Self.samplePlain)
    }

    @Test func decodesFrameWithUncompressedBlock() throws {
        let raw = Data("plain bytes".utf8)
        let frame = Self.frame(blocks: [(raw, uncompressed: true)])
        #expect(try LZ4.decompressFrame(frame, sizeLimit: raw.count) == raw)
    }

    @Test func linkedBlocksMatchAcrossBoundary() throws {
        // Block 2 is a single match (offset 5, length 5) into block 1's output.
        let block1 = Data([0x50]) + Data("hello".utf8)
        let block2 = Data([0x01, 0x05, 0x00])
        let frame = Self.frame(blocks: [
            (block1, uncompressed: false),
            (block2, uncompressed: false)
        ])
        #expect(try LZ4.decompressFrame(frame, sizeLimit: 10) == Data("hellohello".utf8))
    }

    @Test func badMagicThrows() {
        #expect(throws: LZ4Error.badMagic(0x0000_0000)) {
            try LZ4.decompressFrame(Data(count: 16), sizeLimit: 16)
        }
    }

    @Test func invalidMatchOffsetThrows() {
        // Match offset 9 with only 1 byte of output so far.
        let block = Data([0x11, 0x61, 0x09, 0x00])
        var output: [UInt8] = []
        #expect(throws: LZ4Error.invalidOffset(9)) {
            try LZ4.decompressBlock(block, into: &output, sizeLimit: 64)
        }
    }

    @Test func outputOverLimitThrows() {
        var output: [UInt8] = []
        #expect(throws: LZ4Error.outputOverflow(limit: 4)) {
            try LZ4.decompressBlock(Self.sampleBlock, into: &output, sizeLimit: 4)
        }
    }
}
