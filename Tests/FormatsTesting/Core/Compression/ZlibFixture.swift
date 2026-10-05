// Zlib streams built in code, for the decoders that inflate them: compressed
// ESM records, compressed SWF bodies, and the zlib decoder itself.

import Compression
import Foundation

public enum ZlibFixture {
    /// Full RFC 1950 zlib stream: 2-byte header, deflate payload, adler32.
    public static func stream(_ payload: Data) -> Data {
        let capacity = payload.count + 256
        var deflate = Data(count: capacity)
        let written = deflate.withUnsafeMutableBytes { destination in
            payload.withUnsafeBytes { source -> Int in
                guard
                    let destinationBase = destination.baseAddress,
                    let sourceBase = source.baseAddress
                else { return 0 }
                return compression_encode_buffer(
                    destinationBase.assumingMemoryBound(to: UInt8.self),
                    capacity,
                    sourceBase.assumingMemoryBound(to: UInt8.self),
                    payload.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        var out = Data([0x78, 0x9C])
        // Empty input makes the encoder report failure; emit the canonical
        // empty deflate stream (one final stored block) instead.
        out.append(written > 0 ? deflate.prefix(written) : Data([0x03, 0x00]))
        var s1: UInt32 = 1
        var s2: UInt32 = 0
        for byte in payload {
            s1 = (s1 + UInt32(byte)) % 65521
            s2 = (s2 + s1) % 65521
        }
        Swift.withUnsafeBytes(of: ((s2 << 16) | s1).bigEndian) { out.append(contentsOf: $0) }
        return out
    }
}
