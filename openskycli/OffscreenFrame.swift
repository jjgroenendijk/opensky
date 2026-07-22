// Shared offscreen-frame helper for screenshot/interior/bench commands: one
// headless render through the production Renderer, returning the target plus
// the per-frame stats mirrors the commands print.

import Metal
import MetalKit

/// One rendered offscreen frame + the stats the commands report.
struct OffscreenFrame {
    let texture: MTLTexture
    let stats: SceneDrawStats
    let uiStats: UIDrawStats
}

extension RenderCommand {
    /// Probe-stable overlay evidence line (tools/probe.sh greps it).
    static func printUIOverlayStats(_ stats: UIDrawStats) {
        print(
            "[INFO] ui overlay: \(stats.quads) quads, \(stats.glyphs) glyphs, "
                + "\(stats.dropped) dropped, atlas \(stats.atlasWidth)x\(stats.atlasHeight)"
        )
    }

    /// Headless MTKView (never shown, no window) carries the pixel-format
    /// config Renderer reads; renderOffscreen never touches its drawable.
    static func renderOffscreen(
        device: MTLDevice,
        scene: RenderScene,
        camera: SceneCamera,
        size: (width: Int, height: Int),
        timeOfDay: Float,
        uiScene: UIScene = .empty
    ) throws -> OffscreenFrame {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: size.width, height: size.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: scene,
            camera: camera,
            timeOfDay: timeOfDay
        )
        renderer.uiScene = uiScene
        let texture = try renderer.renderOffscreen(width: size.width, height: size.height)
        return OffscreenFrame(
            texture: texture,
            stats: renderer.lastDrawStats,
            uiStats: renderer.lastUIDrawStats
        )
    }
}
