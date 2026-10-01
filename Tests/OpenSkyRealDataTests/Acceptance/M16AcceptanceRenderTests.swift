// Debug overlay acceptance, pixel half: the navigation overlay draws pixels over
// a real navmesh, which the synthetic overlay test cannot show. Three frames in
// checkbox order (nothing, navmesh, navmesh plus corridor), each compared with
// the one before. The detection overlay is not measured: this stage has no
// observers. Frames stay in gitignored `logs/`.

import Foundation
import Metal
import MetalKit
@testable import OpenSkyDiagnostics
@testable import OpenSkyFormatsCore
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

struct M16AcceptanceRenderTests {
    /// How many pixels a toggle has to move before it counts as visible. The
    /// same floor the M14 and M15 render gates use: well above the handful a
    /// rounding difference could touch, far below a whole screen's worth.
    private static let minimumChangedPixels = 200

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func drawsTheRealNavmeshAndCorridorOverTheUsersOwnCell() throws {
        let device = try #require(RealDataEnvironment.device)
        let root = try #require(RealDataEnvironment.dataRoot)
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
