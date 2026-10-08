// Encodes RGBA8 pixels to 2D LDR ASTC blocks with the vendored astcenc, at any
// block size Metal samples and at a chosen encoder effort.

import CASTCEncoder
import Foundation
import Metal

/// A 2D ASTC block footprint. Larger blocks store fewer bits per texel.
nonisolated public struct ASTCBlockSize: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// The linear LDR pixel format, or nil for a footprint Metal does not sample.
    public var pixelFormat: MTLPixelFormat? {
        Self.formats[[width, height]]
    }

    private static let formats: [[Int]: MTLPixelFormat] = [
        [4, 4]: .astc_4x4_ldr, [5, 4]: .astc_5x4_ldr, [5, 5]: .astc_5x5_ldr,
        [6, 5]: .astc_6x5_ldr, [6, 6]: .astc_6x6_ldr, [8, 5]: .astc_8x5_ldr,
        [8, 6]: .astc_8x6_ldr, [8, 8]: .astc_8x8_ldr, [10, 5]: .astc_10x5_ldr,
        [10, 6]: .astc_10x6_ldr, [10, 8]: .astc_10x8_ldr, [10, 10]: .astc_10x10_ldr,
        [12, 10]: .astc_12x10_ldr, [12, 12]: .astc_12x12_ldr
    ]
}

/// astcenc's search effort presets: more effort, better quality, same size.
/// Exhaustive is left out: it takes minutes on a 4096 texture.
nonisolated public enum ASTCEffort: String, CaseIterable, Codable, Sendable {
    case fastest
    case fast
    case medium
    case thorough

    /// The `ASTCENC_PRE_*` value of each preset, from astcenc.h.
    var quality: Float {
        switch self {
        case .fastest: 0
        case .fast: 10
        case .medium: 60
        case .thorough: 98
        }
    }
}

nonisolated public enum ASTCEncoderError: Error, Equatable, Sendable {
    case unsupportedBlock(width: Int, height: Int)
    case encodeFailed(String)
}

nonisolated public enum ASTCEncoder {
    /// The blocks of one image, rows of blocks top first.
    public static func encode(
        _ pixels: TexturePixels,
        block: ASTCBlockSize,
        effort: ASTCEffort
    ) throws -> Data {
        guard block.pixelFormat != nil else {
            throw ASTCEncoderError.unsupportedBlock(width: block.width, height: block.height)
        }
        let size = opensky_astc_encoded_size(
            UInt32(pixels.width), UInt32(pixels.height), UInt32(block.width), UInt32(block.height)
        )
        var blocks = Data(count: size)
        var message = [CChar](repeating: 0, count: 256)
        let status = pixels.rgba.withUnsafeBufferPointer { source in
            blocks.withUnsafeMutableBytes { target in
                opensky_astc_encode(
                    source.baseAddress, UInt32(pixels.width), UInt32(pixels.height),
                    UInt32(block.width), UInt32(block.height), effort.quality,
                    target.baseAddress?.assumingMemoryBound(to: UInt8.self), size,
                    &message, message.count
                )
            }
        }
        guard status == 0 else {
            let bytes = message.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let text = String(bytes: bytes, encoding: .utf8) ?? "status \(status)"
            throw ASTCEncoderError.encodeFailed(text)
        }
        return blocks
    }
}
