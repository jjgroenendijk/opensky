// Pixel/reporting tail of `render`, split from RenderCommand.swift to keep the
// command type below the strict body limit as its overlay options grow.

import Foundation
import Metal

extension RenderCommand {
    static func report(
        _ render: OffscreenFrame,
        scene: RenderScene,
        output: String,
        overlays: (ui: Bool, navmesh: Bool)
    ) throws {
        if overlays.ui {
            printUIOverlayStats(render.uiStats)
        }
        if overlays.navmesh {
            printWorldOverlayStats(render.worldOverlayStats)
        }
        // Instancing evidence (3.2): draw calls collapse below draw-item count
        // only via culling; instances >> draws means repeated models batched.
        print(
            "[INFO] draw calls: \(render.stats.drawCalls) "
                + "(\(scene.drawCount) draw items, \(scene.instanceCount) instances, "
                + "\(render.stats.culledInstances) culled)"
        )
        let pixels = readPixels(texture: render.texture)
        let percent = String(format: "%.1f", nonBackgroundFraction(pixels: pixels) * 100)
        print("[INFO] non-background pixels: \(percent)%")
        let url = URL(filePath: output)
        try FrameScreenshot.write(texture: render.texture, to: url)
        print("[INFO] wrote frame -> \(url.path(percentEncoded: false))")
    }

    /// BGRA readback of the whole offscreen target.
    private static func readPixels(texture: MTLTexture) -> [UInt8] {
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

    /// Fraction of pixels not the black clear color (any channel above a
    /// small noise floor) — quick "did anything draw" signal.
    private static func nonBackgroundFraction(pixels: [UInt8]) -> Double {
        var lit = 0
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            let dark = pixels[pixel] <= 8 && pixels[pixel + 1] <= 8
                && pixels[pixel + 2] <= 8
            if !dark {
                lit += 1
            }
        }
        return Double(lit) / Double(pixels.count / 4)
    }
}
