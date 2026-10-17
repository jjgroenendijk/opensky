// The LZ4 encoder: one raw block through Apple's Compression framework, for the body of
// a Skyrim SE save the export writes. See docs/formats/ess.md.

import Compression
import Foundation

nonisolated extension LZ4 {
    /// Compresses `data` into one raw LZ4 block, the form a Skyrim SE save body takes.
    /// The same input always gives the same bytes.
    public static func compressRawBlock(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        let capacity = data.count + data.count / 255 + 64
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source -> Int in
                guard
                    let destinationBase = destination.baseAddress,
                    let sourceBase = source.baseAddress
                else { return 0 }
                return compression_encode_buffer(
                    destinationBase.assumingMemoryBound(to: UInt8.self), capacity,
                    sourceBase.assumingMemoryBound(to: UInt8.self), data.count,
                    nil, COMPRESSION_LZ4_RAW
                )
            }
        }
        guard written > 0 else { throw LZ4Error.blockEncodeFailed }
        return output.prefix(written)
    }
}
