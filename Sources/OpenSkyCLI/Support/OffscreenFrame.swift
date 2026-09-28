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
    let worldOverlayStats: WorldOverlayDrawStats
}

extension RenderCommand {
    /// Probe-stable overlay evidence line (tools/probe.sh greps it).
    static func printUIOverlayStats(_ stats: UIDrawStats) {
        print(
            "[INFO] ui overlay: \(stats.quads) quads, \(stats.glyphs) glyphs, "
                + "\(stats.dropped) dropped, atlas \(stats.atlasWidth)x\(stats.atlasHeight)"
        )
    }

    static func printWorldOverlayStats(_ stats: WorldOverlayDrawStats) {
        print(
            "[INFO] world overlay: submitted \(stats.submittedPrimitiveCount), "
                + "drawn \(stats.drawnPrimitiveCount) "
                + "(\(stats.triangleCount) triangles, \(stats.lineSegmentCount) lines), "
                + "dropped \(stats.droppedPrimitiveCount), "
                + "truncated \(stats.wasTruncated ? "yes" : "no")"
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
        uiScene: UIScene = .empty,
        navigationOverlayGraph: RuntimeNavigationGraph? = nil,
        detectionOverlay: PerceptionRuntime? = nil
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
        if let navigationOverlayGraph {
            renderer.navmeshOverlayEnabled = true
            renderer.worldOverlaySources.register(identifier: "cli-navigation") { context, list in
                navigationOverlayGraph.appendWorldOverlay(
                    context: context,
                    path: nil,
                    to: &list
                )
            }
        }
        if let detectionOverlay {
            renderer.detectionOverlayEnabled = true
            renderer.worldOverlaySources.register(identifier: "cli-detection") { context, list in
                detectionOverlay.appendWorldOverlay(context: context, to: &list)
            }
        }
        let texture = try renderer.renderOffscreen(width: size.width, height: size.height)
        return OffscreenFrame(
            texture: texture,
            stats: renderer.lastDrawStats,
            uiStats: renderer.lastUIDrawStats,
            worldOverlayStats: renderer.lastWorldOverlayDrawStats
        )
    }
}
