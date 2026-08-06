// Zlib (RFC 1950) stream decoder over Apple's Compression framework.
// COMPRESSION_ZLIB decodes the raw deflate payload only, so the 2-byte zlib
// header is validated and stripped here. The trailing adler32 is not verified
// (deflate self-terminates); output length is validated instead.
//
// Used by compressed plugin records (flag 0x00040000, see docs/formats/esm.md).
// References: RFC 1950 (zlib wrapper), RFC 1951 (deflate).

import Compression
import Foundation

nonisolated enum ZlibError: Error, Equatable {
    /// First two bytes fail the RFC 1950 CMF/FLG check (method 8, mod-31).
    case notZlib
    /// FDICT bit set — preset dictionaries are never used by the game.
    case presetDictionaryUnsupported
    /// Declared output size is negative or over the sanity cap.
    case invalidSize(Int)
    /// Stream is corrupt or does not decode to the declared size.
    case sizeMismatch(expected: Int, actual: Int)
}

nonisolated enum Zlib {
    /// Sanity cap on declared output so a malformed size field cannot balloon
    /// memory. Largest vanilla records (NAVI) are tens of MB.
    static let sizeCap = 1 << 28

    /// Decompresses a full zlib stream (header + deflate + adler32) whose
    /// decompressed size is known up front, as plugin records store it.
    static func decompress(_ stream: Data, decompressedSize: Int) throws -> Data {
        guard decompressedSize >= 0, decompressedSize <= sizeCap else {
            throw ZlibError.invalidSize(decompressedSize)
        }
        guard stream.count >= 2 else { throw ZlibError.notZlib }
        let cmf = stream[stream.startIndex]
        let flg = stream[stream.startIndex + 1]
        guard cmf & 0x0F == 8, (UInt16(cmf) << 8 | UInt16(flg)) % 31 == 0 else {
            throw ZlibError.notZlib
        }
        guard flg & 0x20 == 0 else { throw ZlibError.presetDictionaryUnsupported }
        guard decompressedSize > 0 else { return Data() }

        let deflate = stream.dropFirst(2)
        var output = Data(count: decompressedSize)
        let written = output.withUnsafeMutableBytes { destination in
            deflate.withUnsafeBytes { source -> Int in
                guard
                    let destinationBase = destination.baseAddress,
                    let sourceBase = source.baseAddress
                else { return 0 }
                return compression_decode_buffer(
                    destinationBase.assumingMemoryBound(to: UInt8.self),
                    decompressedSize,
                    sourceBase.assumingMemoryBound(to: UInt8.self),
                    source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written == decompressedSize else {
            throw ZlibError.sizeMismatch(expected: decompressedSize, actual: written)
        }
        return output
    }
}
