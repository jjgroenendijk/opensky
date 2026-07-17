// Clean-room LZ4 decompressor (frame + block formats) for BSA v105 payloads.
// Skyrim SE archives store compressed files as standard LZ4 frames, typically
// with linked blocks; Apple's Compression framework only decodes raw blocks,
// so we decode ourselves into one contiguous buffer (linked-block matches then
// resolve naturally against the full prior output).
//
// References:
//   https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md
//   https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md

import Foundation

nonisolated enum LZ4Error: Error, Equatable {
    case badMagic(UInt32)
    case unsupportedVersion(UInt8)
    case truncatedFrame
    case truncatedBlock
    case invalidOffset(Int)
    case outputOverflow(limit: Int)
}

nonisolated enum LZ4 {
    private static let frameMagic: UInt32 = 0x184D_2204

    /// Decompress a complete LZ4 frame. `sizeLimit` caps the output so a
    /// malicious size field cannot balloon memory.
    static func decompressFrame(_ data: Data, sizeLimit: Int) throws -> Data {
        var reader = BinaryReader(data)
        let hasBlockChecksums = try readFrameHeader(&reader)

        var output: [UInt8] = []
        output.reserveCapacity(min(sizeLimit, 1 << 24))
        while true {
            guard let blockSize = try? reader.readUInt32() else { throw LZ4Error.truncatedFrame }
            if blockSize == 0 {
                break
            } // EndMark
            let length = Int(blockSize & 0x7FFF_FFFF)
            guard let block = try? reader.read(count: length) else {
                throw LZ4Error.truncatedBlock
            }
            if blockSize & 0x8000_0000 != 0 { // stored uncompressed
                guard output.count + block.count <= sizeLimit else {
                    throw LZ4Error.outputOverflow(limit: sizeLimit)
                }
                output.append(contentsOf: block)
            } else {
                try decompressBlock(block, into: &output, sizeLimit: sizeLimit)
            }
            if hasBlockChecksums {
                reader.skip(4)
            } // xxh32 — not verified
        }
        return Data(output)
    }

    /// Validates magic + descriptor, leaves the cursor at the first block.
    /// Returns whether per-block checksums trail each block.
    private static func readFrameHeader(_ reader: inout BinaryReader) throws -> Bool {
        guard reader.bytesRemaining >= 7 else { throw LZ4Error.truncatedFrame }
        let magic = try reader.readUInt32()
        guard magic == frameMagic else { throw LZ4Error.badMagic(magic) }
        let flg = try reader.readUInt8()
        reader.skip(1) // BD (block max size) — irrelevant when decoding to one buffer
        let version = (flg >> 6) & 0b11
        guard version == 1 else { throw LZ4Error.unsupportedVersion(version) }
        if flg & 0b0000_1000 != 0 {
            reader.skip(8)
        } // content size
        if flg & 0b0000_0001 != 0 {
            reader.skip(4)
        } // dictionary ID
        reader.skip(1) // header checksum (HC) — not verified; content validated downstream
        return flg & 0b0001_0000 != 0
    }

    /// Decompress one raw LZ4 block, appending to `output`. Matches may
    /// reference bytes already in `output` (linked blocks).
    static func decompressBlock(
        _ block: Data,
        into output: inout [UInt8],
        sizeLimit: Int
    ) throws {
        let input = [UInt8](block)
        var pos = 0

        while pos < input.count {
            let token = input[pos]
            pos += 1

            var literalLength = Int(token >> 4)
            if literalLength == 15 {
                literalLength += try readLSIC(input, &pos)
            }
            guard pos + literalLength <= input.count else { throw LZ4Error.truncatedBlock }
            guard output.count + literalLength <= sizeLimit else {
                throw LZ4Error.outputOverflow(limit: sizeLimit)
            }
            output.append(contentsOf: input[pos ..< pos + literalLength])
            pos += literalLength

            if pos == input.count {
                break
            } // last sequence: literals only

            guard pos + 2 <= input.count else { throw LZ4Error.truncatedBlock }
            let matchOffset = Int(input[pos]) | (Int(input[pos + 1]) << 8)
            pos += 2
            guard matchOffset > 0, matchOffset <= output.count else {
                throw LZ4Error.invalidOffset(matchOffset)
            }

            var matchLength = Int(token & 0x0F) + 4
            if matchLength == 19 {
                matchLength += try readLSIC(input, &pos)
            }
            guard output.count + matchLength <= sizeLimit else {
                throw LZ4Error.outputOverflow(limit: sizeLimit)
            }
            // Byte-by-byte on purpose: offset < length overlaps (RLE-style runs).
            var src = output.count - matchOffset
            for _ in 0 ..< matchLength {
                output.append(output[src])
                src += 1
            }
        }
    }

    /// Linear small-integer continuation: add 255-valued bytes until one < 255.
    private static func readLSIC(_ input: [UInt8], _ pos: inout Int) throws -> Int {
        var total = 0
        while true {
            guard pos < input.count else { throw LZ4Error.truncatedBlock }
            let byte = input[pos]
            pos += 1
            total += Int(byte)
            if byte != 255 {
                return total
            }
        }
    }
}
