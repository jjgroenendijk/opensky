import CoreGraphics
import Metal
import MetalKit
@testable import OpenSky

/// Readback and A/B comparison for offscreen frames in the real-data render
/// checks, shared so each suite does not carry its own copy.
enum RenderedPixels {
    /// A paused, display-link-free `MTKView` backing a movie-driven renderer
    /// that has no scene of its own — the shape every menu acceptance suite
    /// needs to drive an SWF runtime offscreen.
    @MainActor
    static func offscreenRenderer(device: MTLDevice, width: Int, height: Int) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view)
    }

    /// One movie frame at a fixed animation time, rendered and read back —
    /// the render step every SWF menu acceptance suite repeats to get a
    /// texture and its pixels together.
    @MainActor
    static func renderFrame(
        _ renderer: Renderer,
        width: Int,
        height: Int
    ) throws -> (texture: MTLTexture, pixels: [UInt8]) {
        let texture = try renderer.renderOffscreen(width: width, height: height, animationTime: 1)
        return (texture, read(texture))
    }

    /// The texture's BGRA8 bytes, row after row.
    static func read(_ texture: MTLTexture) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return pixels
    }

    /// Pixels whose four bytes differ at all. Frames of different sizes count
    /// every pixel of the larger one as changed.
    static func changedCount(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) / 4 }
        return stride(from: 0, to: lhs.count, by: 4).count { index in
            lhs[index ..< index + 4] != rhs[index ..< index + 4]
        }
    }

    /// Pixels where any colour channel moved by more than `tolerance`, which
    /// ignores the alpha byte and dithering-level noise.
    static func changedCount(_ lhs: [UInt8], _ rhs: [UInt8], tolerance: Int) -> Int {
        stride(from: 0, to: min(lhs.count, rhs.count), by: 4).reduce(0) { count, index in
            let changed = (0 ..< 3).contains {
                abs(Int(lhs[index + $0]) - Int(rhs[index + $0])) > tolerance
            }
            return count + (changed ? 1 : 0)
        }
    }
}
