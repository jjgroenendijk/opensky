// M16 acceptance, pixel half (issue #203): the world-space debug overlays are
// drawn over the user's own cell, and the change is measured as changed-pixel
// counts rather than eyeballed.
//
// `WorldOverlayTests.offscreenOverlayProducesPixelDelta` already proves the
// overlay pass draws a triangle a test handed it. What it cannot prove is that
// the *navigation source* over a real navmesh puts pixels on a real frame: the
// synthetic case registers its own source and never touches
// `RuntimeNavigationGraph`, so a graph that produced an empty draw list for
// vanilla geometry would leave it green.
//
// Three frames, in the order a user switches the checkboxes in: nothing, the
// navmesh, then the navmesh and the corridor together. Each is compared against
// the one before it, so each toggle is shown to be doing something of its own
// rather than the pair being shown to do something between them.
//
// The detection overlay is deliberately not measured here. It is drawn by
// `PerceptionRuntime.appendWorldOverlay` from live observers, and this stage has
// no perception pass attached to it — a frame with no observers in it would
// measure zero and prove nothing. `PerceptionOverlayTests` covers the geometry
// it builds, and the M16 gate panel's own suite covers the toggle.
//
// Gated on a Metal 4 device *and* on the install, because what is being drawn is
// the user's own cell geometry.
//
// Rendered frames go to gitignored `logs/`: a frame embeds the user's game art
// and is never committed (AGENTS.md "Legal & IP boundary").

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct M16AcceptanceRenderTests {
    /// How many pixels a toggle has to move before it counts as visible. The
    /// same floor the M14 and M15 render gates use: well above the handful a
    /// rounding difference could touch, far below a whole screen's worth.
    private static let minimumChangedPixels = 200

    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        device != nil && dataRoot != nil
    }

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func drawsTheRealNavmeshAndCorridorOverTheUsersOwnCell() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let assembled = try PlayerBodyFixture.assemble(device: device, root: root)
        let scene = try assembled.builder.buildScene(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: WalkPathRoute.farmCell.x,
            gridY: WalkPathRoute.farmCell.y
        )
        let bounds = try #require(scene.bounds, "no cell bounds — nothing drew")
        #expect(!scene.navmeshes.isEmpty, "the farm cell decoded no navmesh to draw")

        let renderer = try FirstPersonRenderRealDataTests.renderer(
            device: device, scene: scene, bounds: bounds
        )
        var route = try RealNavigationFixture.route(root: root)
        let corridor = route.graph.findPath(NavigationPathQuery(
            start: route.start, target: route.target
        ))
        guard case let .path(path) = corridor else {
            Issue.record("the real exterior-to-interior corridor missed")
            throw M16RenderError.noPath
        }
        let graph = route.graph
        renderer.worldOverlaySources.register(identifier: "navigation") { context, list in
            graph.appendWorldOverlay(context: context, path: path, to: &list)
        }

        try Self.expectEachToggleMovesPixels(renderer)
    }

    /// Nothing, then the navmesh, then the corridor on top of it. Each frame is
    /// compared against the one before, and the draw stats are read back beside
    /// the pixel count so a frame that changed for some other reason cannot pass
    /// as an overlay.
    @MainActor
    private static func expectEachToggleMovesPixels(_ renderer: Renderer) throws {
        renderer.navmeshOverlayEnabled = false
        renderer.pathOverlayEnabled = false
        let plain = try FirstPersonRenderRealDataTests.frame(renderer)
        #expect(renderer.lastWorldOverlayDrawStats.drawnPrimitiveCount == 0)

        renderer.navmeshOverlayEnabled = true
        let withNavmesh = try FirstPersonRenderRealDataTests.frame(renderer)
        let navmeshStats = renderer.lastWorldOverlayDrawStats
        #expect(navmeshStats.triangleCount > 0, "the real navmesh submitted no triangles")
        let navmeshDelta = FirstPersonRenderRealDataTests.changedPixels(plain, withNavmesh)
        #expect(
            navmeshDelta >= minimumChangedPixels,
            "the navmesh overlay moved \(navmeshDelta) pixels"
        )

        renderer.pathOverlayEnabled = true
        let withCorridor = try FirstPersonRenderRealDataTests.frame(renderer)
        let corridorStats = renderer.lastWorldOverlayDrawStats
        #expect(
            corridorStats.lineSegmentCount > 0,
            "the corridor overlay submitted no waypoint line"
        )
        #expect(corridorStats.submittedPrimitiveCount > navmeshStats.submittedPrimitiveCount)
        let corridorDelta = FirstPersonRenderRealDataTests.changedPixels(
            withNavmesh, withCorridor
        )
        #expect(
            corridorDelta >= minimumChangedPixels,
            "the corridor overlay moved \(corridorDelta) pixels"
        )

        try FirstPersonRenderRealDataTests.writePNG(plain, name: "m16-overlays-off.png")
        try FirstPersonRenderRealDataTests.writePNG(
            withCorridor, name: "m16-overlays-on.png"
        )
        print(
            "[INFO] M16 overlay pixel delta: navmesh \(navmeshDelta) px"
                + " (\(navmeshStats.triangleCount) triangles),"
                + " corridor \(corridorDelta) px"
                + " (\(corridorStats.lineSegmentCount) line segments)"
        )
    }
}

/// Thrown only to end the run early when the real corridor misses, which
/// `Issue.record` has already reported.
private enum M16RenderError: Error {
    case noPath
}
