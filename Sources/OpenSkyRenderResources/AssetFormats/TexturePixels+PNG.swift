// Reads an image file into RGBA8 pixels, so two captures can be compared with
// `TextureImageDifference`, such as a frame with the asset cache on and off.

import CoreGraphics
import Foundation
import ImageIO

nonisolated public enum TexturePixelsImageError: Error, Equatable {
    case unreadable(URL)
}

nonisolated extension TexturePixels {
    /// `size` scales the image as it is read, such as a Retina window capture to points.
    public init(contentsOf url: URL, size: (width: Int, height: Int)? = nil) throws {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw TexturePixelsImageError.unreadable(url) }
        let width = size?.width ?? image.width
        let height = size?.height ?? image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { raw in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw TexturePixelsImageError.unreadable(url) }
        self.init(width: width, height: height, rgba: rgba)
    }

    /// The pixels as an opaque sRGB image, for a PNG.
    public func cgImage() -> CGImage? {
        guard
            let provider = CGDataProvider(data: Data(rgba) as CFData),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
