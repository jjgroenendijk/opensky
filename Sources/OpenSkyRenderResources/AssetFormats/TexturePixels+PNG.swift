// Reads an image file into RGBA8 pixels, so two captures can be compared with
// `TextureImageDifference`, such as a frame with the asset cache on and off.

import CoreGraphics
import Foundation
import ImageIO

nonisolated public enum TexturePixelsImageError: Error, Equatable {
    case unreadable(URL)
}

nonisolated extension TexturePixels {
    public init(contentsOf url: URL) throws {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw TexturePixelsImageError.unreadable(url) }
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { raw in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw TexturePixelsImageError.unreadable(url) }
        self.init(width: width, height: height, rgba: rgba)
    }
}
