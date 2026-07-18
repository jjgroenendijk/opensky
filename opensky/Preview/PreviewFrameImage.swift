// Offscreen BGRA render target -> CGImage for the preview detail pane. Same
// readback the render tests use; shared so the env-gated preview test can
// assert on the exact image the GUI would show.

import CoreGraphics
import Metal

nonisolated enum PreviewFrameImage {
    /// Reads back a shared-storage BGRA8 offscreen texture into an sRGB
    /// CGImage. Nil only when Core Graphics refuses the buffer.
    static func cgImage(from texture: MTLTexture) -> CGImage? {
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
}
