// Shared rendered-frame screenshot conversion + PNG output. App, CLI, preview,
// and render tests all feed the same CPU-readable BGRA8 or half-float texture path.

public import CoreGraphics
public import Foundation
import ImageIO
public import Metal
import UniformTypeIdentifiers

public enum FrameScreenshotError: LocalizedError {
    case imageCreationFailed
    case destinationCreationFailed(URL)
    case writeFailed(URL)

    public var errorDescription: String? {
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

nonisolated public enum FrameScreenshot: Sendable {
    /// Reads a shared-storage BGRA8 or half-float render target into an sRGB CGImage.
    public static func image(from texture: any MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        var pixels = bgraBytes(of: texture)
        return pixels.withUnsafeMutableBytes { bytes -> CGImage? in
            guard
                let base = bytes.baseAddress,
                let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                let context = unsafe CGContext(
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

    /// The pixels of a shared-storage render target as RGBA8 rows, top first.
    public static func rgbaBytes(from texture: any MTLTexture) -> Data {
        var pixels = bgraBytes(of: texture)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels.swapAt(offset, offset + 2)
        }
        return Data(pixels)
    }

    /// sRGB BGRA8 bytes. A half-float target holds linear colour, which is encoded here.
    static func bgraBytes(of texture: any MTLTexture) -> [UInt8] {
        let width = texture.width
        let height = texture.height
        let region = MTLRegionMake2D(0, 0, width, height)
        guard texture.pixelFormat == .rgba16Float else {
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            pixels.withUnsafeMutableBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                unsafe texture.getBytes(base, bytesPerRow: width * 4, from: region, mipmapLevel: 0)
            }
            return pixels
        }
        var halves = [Float16](repeating: 0, count: width * height * 4)
        halves.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            unsafe texture.getBytes(base, bytesPerRow: width * 8, from: region, mipmapLevel: 0)
        }
        return bgraBytes(linearRGBA: halves.map { Float($0) })
    }

    /// Linear RGBA values to sRGB-encoded BGRA8 bytes, clamped to 0...1.
    static func bgraBytes(linearRGBA values: [Float]) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: values.count)
        for pixel in stride(from: 0, to: values.count - 3, by: 4) {
            pixels[pixel] = srgbByte(values[pixel + 2])
            pixels[pixel + 1] = srgbByte(values[pixel + 1])
            pixels[pixel + 2] = srgbByte(values[pixel])
            pixels[pixel + 3] = UInt8((min(max(values[pixel + 3], 0), 1) * 255).rounded())
        }
        return pixels
    }

    static func srgbByte(_ linear: Float) -> UInt8 {
        let value = min(max(linear, 0), 1)
        let encoded = value <= 0.003_130_8 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
        return UInt8((encoded * 255).rounded())
    }

    public static func write(texture: any MTLTexture, to url: URL) throws {
        guard let image = image(from: texture) else {
            throw FrameScreenshotError.imageCreationFailed
        }
        try write(image: image, to: url)
    }

    public static func write(image: CGImage, to url: URL) throws {
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
