// Shared rendered-frame screenshot conversion + PNG output. App, CLI, preview,
// and render tests all feed the same CPU-readable BGRA texture path.

import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

enum FrameScreenshotError: LocalizedError {
    case imageCreationFailed
    case destinationCreationFailed(URL)
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .imageCreationFailed:
            "Cannot create an image from the rendered frame."
        case let .destinationCreationFailed(url):
            "Cannot create a PNG encoder for \(url.path(percentEncoded: false))."
        case let .writeFailed(url):
            "Cannot write PNG to \(url.path(percentEncoded: false))."
        }
    }
}

nonisolated enum FrameScreenshot {
    /// Reads a shared-storage BGRA8 render target into an sRGB CGImage.
    static func image(from texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let base = bytes.baseAddress else { return nil } // non-empty
            texture.getBytes(
                base,
                bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
            guard
                let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue
                )
            else { return nil }
            return context.makeImage()
        }
    }

    static func write(texture: MTLTexture, to url: URL) throws {
        guard let image = image(from: texture) else {
            throw FrameScreenshotError.imageCreationFailed
        }
        try write(image: image, to: url)
    }

    static func write(image: CGImage, to url: URL) throws {
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw FrameScreenshotError.destinationCreationFailed(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FrameScreenshotError.writeFailed(url)
        }
    }
}
