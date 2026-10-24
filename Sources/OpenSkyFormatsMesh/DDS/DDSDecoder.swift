// CPU decode of a DDS top level to RGBA8, for textures the engine paints on the
// CPU: the chargen face color map (BC1) and the tint masks (24-bit RGB).
// Layout and sources: docs/formats/dds.md, "CPU decode".

import Foundation
import OpenSkyImageKernels

nonisolated public enum DDSDecoder {
    /// BC1, BC3, 32-bit RGB, and 24-bit RGB. Other formats throw `unsupported`.
    public static func topLevel(_ data: Data) throws -> DecodedImage {
        try decode(DDSFile(data: data), level: 0)
    }

    /// The smallest mip with both edges at least `edge`, or the top level if none is.
    public static func smallLevel(_ data: Data, edge: Int) throws -> DecodedImage {
        let file = try DDSFile(data: data)
        let fits = (0 ..< file.mipCount).filter {
            file.width(level: $0) >= edge && file.height(level: $0) >= edge
        }
        return try decode(file, level: fits.last ?? 0)
    }

    private static func decode(_ file: DDSFile, level index: Int) throws -> DecodedImage {
        let level = file.mipData(level: index)
        let width = file.width(level: index)
        let height = file.height(level: index)
        let bytes = [UInt8](level)
        let rgba: [UInt8] = switch file.format {
        case .bc1: BlockDecoder.bc1(bytes, width: width, height: height)
        case .bc3: BlockDecoder.bc3(bytes, width: width, height: height)
        case .rgba8888: bytes
        case .bgra8888, .xrgb8888:
            BlockDecoder.swizzleBGRA(bytes, opaque: file.format == .xrgb8888)
        default: throw DDSError.unsupported("CPU decode of \(file.format)")
        }
        return DecodedImage(width: width, height: height, rgba: rgba)
    }
}
