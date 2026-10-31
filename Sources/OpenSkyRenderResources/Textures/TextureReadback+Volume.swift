// Reads the slices of a shared-storage volume texture back to RGBA8, so a tool can
// show each one as an image.

import Metal

nonisolated public enum TextureReadbackError: Error, Equatable {
    case notAVolume
    /// The raw `MTLPixelFormat` value. Only 8-bit RGBA and BGRA read back.
    case unsupportedFormat(UInt)
}

nonisolated extension TextureReadback {
    /// Every slice of one level, front to back, as stored.
    public static func volumeSlices(of texture: MTLTexture, level: Int) throws -> [TexturePixels] {
        guard texture.textureType == .type3D else { throw TextureReadbackError.notAVolume }
        let swapsRedAndBlue: Bool
        switch texture.pixelFormat {
        case .bgra8Unorm, .bgra8Unorm_srgb: swapsRedAndBlue = true
        case .rgba8Unorm, .rgba8Unorm_srgb: swapsRedAndBlue = false
        default: throw TextureReadbackError.unsupportedFormat(texture.pixelFormat.rawValue)
        }
        let width = max(1, texture.width >> level)
        let height = max(1, texture.height >> level)
        let depth = max(1, texture.depth >> level)
        return (0 ..< depth).map { slice in
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(
                &rgba,
                bytesPerRow: width * 4,
                bytesPerImage: width * height * 4,
                from: MTLRegionMake3D(0, 0, slice, width, height, 1),
                mipmapLevel: level,
                slice: 0
            )
            if swapsRedAndBlue {
                for offset in stride(from: 0, to: rgba.count, by: 4) {
                    rgba.swapAt(offset, offset + 2)
                }
            }
            return TexturePixels(width: width, height: height, rgba: rgba)
        }
    }
}
