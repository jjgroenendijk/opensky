// Pure overlay-buffer coverage plus the offscreen GPU pixel-delta proof for
// issue #422. All geometry is synthetic and built in code.

import Metal
import MetalKit
@testable import opensky
import OpenSkyShaderTypes
import simd
import Testing

struct WorldOverlayTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    @Test
    func builderPreservesVertexColorsAndAppliesPrimitiveCap() {
        let red = SIMD4<Float>(1, 0, 0, 0.5)
        let green = SIMD4<Float>(0, 1, 0, 0.75)
        let blue = SIMD4<Float>(0, 0, 1, 1)
        var list = WorldOverlayDrawList()
        list.addTriangle(
            WorldOverlayPoint(position: SIMD3(1, 2, 3), color: red),
            WorldOverlayPoint(position: SIMD3(4, 5, 6), color: green),
            WorldOverlayPoint(position: SIMD3(7, 8, 9), color: blue)
        )
        list.addLineSegment(SIMD3(10, 11, 12), SIMD3(13, 14, 15), color: green)
        list.addTriangle(.zero, SIMD3(1, 0, 0), SIMD3(0, 1, 0), color: blue)

        let result = list.budgeted(maxPrimitives: 2)

        #expect(result.submittedPrimitiveCount == 3)
        #expect(result.drawnPrimitiveCount == 2)
        #expect(result.triangleCount == 1)
        #expect(result.lineSegmentCount == 1)
        #expect(result.droppedPrimitiveCount == 1)
        #expect(result.vertices.count == 5)
        #expect(result.vertices[0].position == SIMD3(1, 2, 3))
        #expect(result.vertices[0].color == red)
        #expect(result.vertices[1].color == green)
        #expect(result.vertices[2].color == blue)
        #expect(result.vertices[3].position == SIMD3(10, 11, 12))
        #expect(result.vertices[4].position == SIMD3(13, 14, 15))
        #expect(result.vertices[3].color == green)
    }

    @Test
    func polylineCreatesSegmentsAndNegativeCapDropsEverything() {
        var list = WorldOverlayDrawList()
        list.addPolyline(
            [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0)],
            color: SIMD4(1, 1, 0, 1)
        )

        #expect(list.primitiveCount == 2)
        let result = list.budgeted(maxPrimitives: -1)
        #expect(result.drawnPrimitiveCount == 0)
        #expect(result.droppedPrimitiveCount == 2)
        #expect(result.vertices.isEmpty)
    }

    @Test
    @MainActor
    func registryKeepsOrderAndReplacesAnIdentifierInPlace() {
        let registry = WorldOverlaySourceRegistry()
        registry.register(identifier: "first") { _, list in
            list.addLineSegment(.zero, SIMD3(1, 0, 0), color: SIMD4(1, 0, 0, 1))
        }
        registry.register(identifier: "second") { _, list in
            list.addLineSegment(.zero, SIMD3(2, 0, 0), color: SIMD4(0, 1, 0, 1))
        }
        registry.register(identifier: "first") { _, list in
            list.addLineSegment(.zero, SIMD3(3, 0, 0), color: SIMD4(0, 0, 1, 1))
        }

        let context = WorldOverlayFrameContext(
            navmeshOverlayEnabled: false,
            pathOverlayEnabled: false
        )
        let result = registry.makeDrawList(context: context).budgeted(maxPrimitives: 10)
        #expect(registry.sourceCount == 2)
        #expect(result.vertices[1].position == SIMD3(3, 0, 0))
        #expect(result.vertices[3].position == SIMD3(2, 0, 0))

        registry.remove(identifier: "first")
        #expect(registry.sourceCount == 1)
    }

    @Test
    @MainActor
    func navigationSourceBuildsResidentFillCorridorAndWaypointLine() throws {
        let mesh = try NavigationRuntimeFixture.grid(id: 0x100, columns: 2, rows: 2)
        let location = CellSceneLocation.interior(FormID(1))
        var graph = RuntimeNavigationGraph()
        graph.setCell(location, scene: NavigationRuntimeFixture.scene(
            location: location,
            navmeshes: [mesh]
        ))
        let pathResult = graph.findPath(NavigationPathQuery(
            start: SIMD3(1, 1, 0),
            target: SIMD3(19, 19, 0),
            capsuleRadius: 0,
            projectionRadius: 4
        ))
        guard case let .path(path) = pathResult else {
            Issue.record("synthetic navigation path missed")
            return
        }
        var list = WorldOverlayDrawList()
        graph.appendWorldOverlay(
            context: WorldOverlayFrameContext(
                navmeshOverlayEnabled: true,
                pathOverlayEnabled: true
            ),
            path: path,
            to: &list
        )
        let result = list.budgeted(maxPrimitives: 1000)

        #expect(result.triangleCount == graph.triangleCount + path.corridor.count)
        #expect(result.lineSegmentCount == max(path.waypoints.count - 1, 0))
        #expect(result.droppedPrimitiveCount == 0)
        #expect(result.vertices[0].color.w == 0.22)
        #expect(result.vertices[result.triangleVertexCount - 1].color.w == 0.42)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func offscreenOverlayProducesPixelDelta() throws {
        let renderer = try Self.makeRenderer()
        let baseline = try Self.pixels(renderer.renderOffscreen(
            width: 480,
            height: 320,
            animationTime: 1
        ))
        renderer.worldOverlaySources.register(identifier: "synthetic") { _, list in
            list.addTriangle(
                SIMD3(-220, -180, 8),
                SIMD3(220, -180, 8),
                SIMD3(0, 220, 8),
                color: SIMD4(1, 0.05, 0.05, 0.8)
            )
        }
        let overlaid = try Self.pixels(renderer.renderOffscreen(
            width: 480,
            height: 320,
            animationTime: 1
        ))
        let changed = Self.changedPixels(baseline, overlaid)

        #expect(changed > 1000, "world overlay changed only \(changed) pixels")
        #expect(renderer.lastWorldOverlayDrawStats.submittedPrimitiveCount == 1)
        #expect(renderer.lastWorldOverlayDrawStats.drawnPrimitiveCount == 1)
        #expect(renderer.lastWorldOverlayDrawStats.triangleCount == 1)
        #expect(!renderer.lastWorldOverlayDrawStats.wasTruncated)
    }

    @MainActor
    private static func makeRenderer() throws -> Renderer {
        let device = try #require(self.device)
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 480, height: 320), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view)
    }

    private static func pixels(_ texture: MTLTexture) -> [UInt8] {
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

    private static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        stride(from: 0, to: lhs.count, by: 4).reduce(into: 0) { changed, pixel in
            let delta = (0 ..< 3).map {
                abs(Int(lhs[pixel + $0]) - Int(rhs[pixel + $0]))
            }.max() ?? 0
            if delta > 8 {
                changed += 1
            }
        }
    }
}
