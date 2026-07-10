// Offscreen smoke render of the full static-mesh path: real Renderer, real
// MTKView drawable (no window), real DemoScene. Deterministic pixel checks
// (AGENTS.md testing rule) plus a temp PNG for human eyes — logged so
// renderer changes stay visually verifiable without Screen Recording TCC.
// Skips when the machine lacks a Metal 4 GPU (paravirtual CI).

import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalKit
@testable import opensky
import Testing
import UniformTypeIdentifiers

struct RendererOffscreenTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func rendersDemoSceneOffscreen() throws {
        let device = try #require(Self.device)
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 480, height: 320), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false

        let renderer = try Renderer(view: view)
        // Synchronous offscreen frame — no window, no drawable, no timing
        // races. Render twice to prove the ring/event bookkeeping survives
        // consecutive frames.
        _ = try renderer.renderOffscreen(width: 480, height: 320)
        let texture = try renderer.renderOffscreen(width: 480, height: 320)

        let width = texture.width
        let height = texture.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return } // non-empty
            texture.getBytes(
                base,
                bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }

        // The scene must actually shade: more distinct colors than clear +
        // a flat silhouette could produce, and the checkerboard ground must
        // put lit geometry in the frame center.
        var distinct = Set<UInt32>()
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            let bgra = UInt32(pixels[pixel]) << 24 | UInt32(pixels[pixel + 1]) << 16
                | UInt32(pixels[pixel + 2]) << 8 | UInt32(pixels[pixel + 3])
            distinct.insert(bgra)
        }
        #expect(distinct.count > 50, "rendered frame is too uniform — scene missing?")

        let center = ((height / 2) * width + width / 2) * 4
        let centerIsClearColor = pixels[center] == 0 && pixels[center + 1] == 0
            && pixels[center + 2] == 0
        #expect(!centerIsClearColor, "frame center is background — no geometry drawn")

        try writePNG(pixels: pixels, width: width, height: height)
    }

    /// Dumps the BGRA frame to a temp PNG and logs the path for human review.
    private func writePNG(pixels: [UInt8], width: Int, height: Int) throws {
        var data = pixels
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-offscreen-\(UUID().uuidString).png")
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        print("[INFO] offscreen frame: \(url.path)")
    }
}
