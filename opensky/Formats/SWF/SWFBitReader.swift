// MSB-first bit reader for SWF's bit-packed fields (RECT, matrices, colors).
// SWF packs unsigned/signed bit fields most-significant-bit first within each
// byte, spanning byte boundaries; the byte-aligned BinaryReader cannot express
// this, and the repo has no other bit reader, so this is the one place we walk
// individual bits.
//
// Reference: Adobe SWF File Format Specification, version 19, "Bit values" and
// the UB[n] / SB[n] primitive types.

import Foundation

nonisolated enum SWFBitReaderError: Error, Equatable {
    /// Requested more bits than remain in the backing bytes.
    case outOfBounds(bitsRequested: Int, bitsRemaining: Int)
    /// A field width outside the representable 0...32 range was requested.
    case invalidBitCount(Int)
}

/// Sequential most-significant-bit-first cursor over a `Data`. Value type.
nonisolated struct SWFBitReader {
    private let data: Data
    /// Absolute bit index from the start of `data` (0 = MSB of first byte).
    private(set) var bitPosition: Int

    init(_ data: Data) {
        self.data = data
        bitPosition = 0
    }

    /// Byte index of the cursor. Exact only when byte-aligned (see `align()`);
    /// callers align before handing the offset to a byte reader.
    var byteOffset: Int {
        bitPosition / 8
    }

    /// Advances to the next byte boundary, discarding leftover bits. SWF
    /// byte-aligns after a run of bit fields such as the FrameSize RECT.
    mutating func align() {
        let remainder = bitPosition % 8
        if remainder != 0 {
            bitPosition += 8 - remainder
        }
    }

    /// Reads an unsigned `bits`-wide big-endian field (UB[bits]).
    mutating func readUB(_ bits: Int) throws -> UInt32 {
        guard bits >= 0, bits <= 32 else {
            throw SWFBitReaderError.invalidBitCount(bits)
        }
        guard bits > 0 else { return 0 }
        let remaining = data.count * 8 - bitPosition
        guard bits <= remaining else {
            throw SWFBitReaderError.outOfBounds(bitsRequested: bits, bitsRemaining: remaining)
        }
        var value: UInt32 = 0
        for _ in 0 ..< bits {
            let byte = data[data.startIndex + bitPosition / 8]
            let bit = (byte >> (7 - bitPosition % 8)) & 1
            value = (value << 1) | UInt32(bit)
            bitPosition += 1
        }
        return value
    }

    /// Reads a signed `bits`-wide two's-complement field (SB[bits]), sign
    /// extended from the top bit into a full `Int32`.
    mutating func readSB(_ bits: Int) throws -> Int32 {
        let raw = try readUB(bits)
        guard bits > 0, raw & (1 << (bits - 1)) != 0 else {
            return Int32(bitPattern: raw)
        }
        // Negative: set every bit above the field width so the pattern is a
        // valid two's-complement Int32.
        let mask: UInt32 = bits == 32 ? .max : (1 << bits) - 1
        return Int32(bitPattern: raw | ~mask)
    }
}
