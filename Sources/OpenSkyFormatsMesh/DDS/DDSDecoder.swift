// CPU decode of a DDS top level to RGBA8, for textures the engine paints on the
// CPU: the chargen face color map (BC1) and the tint masks (24-bit RGB).
// Layout and sources: docs/formats/dds.md, "CPU decode".

import Foundation
import OpenSkyImageKernels

nonisolated public enum DDSDecoder {
    /// BC1, BC3, 32-bit RGB, and 24-bit RGB. Other formats throw `unsupported`.
    public static func topLevel(_ data: Data) throws -> DecodedImage {
        let file = try DDSFile(data: data)
        let level = file.mipData(level: 0)
        let width = file.width
        let height = file.height
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
