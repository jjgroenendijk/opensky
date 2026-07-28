// Clean-room LZ4 frame parser for BSA v105 payloads. Independent raw blocks
// use Apple's Compression framework; linked blocks retain the local decoder
// because their matches can reach into prior output.
//
// References:
//   https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md
//   https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md

import Compression
import Foundation

nonisolated enum LZ4Error: Error, Equatable {
    case badMagic(UInt32)
    case unsupportedVersion(UInt8)
    case unsupportedBlockMaximum(UInt8)
    case truncatedFrame
    case truncatedBlock
    case blockDecodeFailed
    case invalidOffset(Int)
    case outputOverflow(limit: Int)
}

nonisolated enum LZ4 {
    private static let frameMagic: UInt32 = 0x184D_2204

    private struct FrameDescriptor {
        let blocksIndependent: Bool
        let hasBlockChecksums: Bool
        let maximumBlockSize: Int
    }

    /// Decompress a complete LZ4 frame. `sizeLimit` caps the output so a
    /// malicious size field cannot balloon memory.
    static func decompressFrame(_ data: Data, sizeLimit: Int) throws -> Data {
        var reader = BinaryReader(data)
        let descriptor = try readFrameHeader(&reader)
        if descriptor.blocksIndependent {
            return try decompressIndependentBlocks(
                reader: &reader,
                descriptor: descriptor,
                sizeLimit: sizeLimit
            )
        }
        return try decompressLinkedBlocks(
            reader: &reader,
            hasBlockChecksums: descriptor.hasBlockChecksums,
            sizeLimit: sizeLimit
        )
    }

    /// Linked blocks can match against any prior output byte, so retain one
    /// contiguous array and the defensive local block decoder.
    private static func decompressLinkedBlocks(
        reader: inout BinaryReader,
        hasBlockChecksums: Bool,
        sizeLimit: Int
    ) throws -> Data {
        var output: [UInt8] = []
        output.reserveCapacity(min(sizeLimit, 1 << 24))
        while true {
            let (block, uncompressed) = try readBlock(&reader)
            guard let block else { break }
            if uncompressed {
                try appendUncompressed(block, to: &output, sizeLimit: sizeLimit)
            } else {
                try decompressBlock(block, into: &output, sizeLimit: sizeLimit)
            }
            if hasBlockChecksums {
                guard reader.bytesRemaining >= 4 else { throw LZ4Error.truncatedFrame }
                reader.skip(4)
            }
        }
        return Data(output)
    }

    /// Independent blocks cannot refer to earlier output, so the platform's
    /// raw LZ4 decoder can process each one without a dictionary.
    private static func decompressIndependentBlocks(
        reader: inout BinaryReader,
        descriptor: FrameDescriptor,
        sizeLimit: Int
    ) throws -> Data {
        var output = Data()
        output.reserveCapacity(min(sizeLimit, 1 << 24))
        while true {
            let (block, uncompressed) = try readBlock(&reader)
            guard let block else { break }
            if uncompressed {
                guard output.count + block.count <= sizeLimit else {
                    throw LZ4Error.outputOverflow(limit: sizeLimit)
                }
                output.append(block)
            } else {
                let remaining = max(0, sizeLimit - output.count)
                let capacity = min(descriptor.maximumBlockSize, remaining + 1)
                var decoded = Data(count: capacity)
                let written = decoded.withUnsafeMutableBytes { destination in
                    block.withUnsafeBytes { source -> Int in
                        guard
                            let destinationBase = destination.baseAddress,
                            let sourceBase = source.baseAddress
                        else { return 0 }
                        return compression_decode_buffer(
                            destinationBase.assumingMemoryBound(to: UInt8.self),
                            destination.count,
                            sourceBase.assumingMemoryBound(to: UInt8.self),
                            source.count,
                            nil,
                            COMPRESSION_LZ4_RAW
                        )
                    }
                }
                guard written > 0 else { throw LZ4Error.blockDecodeFailed }
                guard written <= remaining else {
                    throw LZ4Error.outputOverflow(limit: sizeLimit)
                }
                output.append(decoded.prefix(written))
            }
            if descriptor.hasBlockChecksums {
                guard reader.bytesRemaining >= 4 else { throw LZ4Error.truncatedFrame }
                reader.skip(4)
            }
        }
        return output
    }

    /// Reads one frame block. nil marks the EndMark.
    private static func readBlock(
        _ reader: inout BinaryReader
    ) throws -> (data: Data?, uncompressed: Bool) {
        guard let blockSize = try? reader.readUInt32() else {
            throw LZ4Error.truncatedFrame
        }
        if blockSize == 0 {
            return (nil, false)
        }
        let length = Int(blockSize & 0x7FFF_FFFF)
        guard let block = try? reader.read(count: length) else {
            throw LZ4Error.truncatedBlock
        }
        return (block, blockSize & 0x8000_0000 != 0)
    }

    private static func appendUncompressed(
        _ block: Data,
        to output: inout [UInt8],
        sizeLimit: Int
    ) throws {
        guard output.count + block.count <= sizeLimit else {
            throw LZ4Error.outputOverflow(limit: sizeLimit)
        }
        output.append(contentsOf: block)
    }

    /// Validates magic + descriptor, leaves the cursor at the first block.
    private static func readFrameHeader(
        _ reader: inout BinaryReader
    ) throws -> FrameDescriptor {
        guard reader.bytesRemaining >= 7 else { throw LZ4Error.truncatedFrame }
        let magic = try reader.readUInt32()
        guard magic == frameMagic else { throw LZ4Error.badMagic(magic) }
        let flg = try reader.readUInt8()
        let bd = try reader.readUInt8()
        let version = (flg >> 6) & 0b11
        guard version == 1 else { throw LZ4Error.unsupportedVersion(version) }
        let blockMaximumCode = (bd >> 4) & 0b111
        let maximumBlockSize: Int
        switch blockMaximumCode {
        case 4: maximumBlockSize = 64 << 10
        case 5: maximumBlockSize = 256 << 10
        case 6: maximumBlockSize = 1 << 20
        case 7: maximumBlockSize = 4 << 20
        default: throw LZ4Error.unsupportedBlockMaximum(blockMaximumCode)
        }
        let optionalByteCount =
            (flg & 0b0000_1000 != 0 ? 8 : 0)
                + (flg & 0b0000_0001 != 0 ? 4 : 0)
                + 1
        guard reader.bytesRemaining >= optionalByteCount else {
            throw LZ4Error.truncatedFrame
        }
        if flg & 0b0000_1000 != 0 {
            reader.skip(8)
        } // content size
        if flg & 0b0000_0001 != 0 {
            reader.skip(4)
        } // dictionary ID
        reader.skip(1) // header checksum (HC) — not verified; content validated downstream
        return FrameDescriptor(
            blocksIndependent: flg & 0b0010_0000 != 0,
            hasBlockChecksums: flg & 0b0001_0000 != 0,
            maximumBlockSize: maximumBlockSize
        )
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
