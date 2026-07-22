// M7.5.2 GRAS render acceptance against the user's read-only Skyrim SE
// install. Renders cell-owned Whiterun grass through production batches,
// proves live density/distance policy + weather wind motion numerically, and
// writes only gitignored PNG/report evidence. One @Test keeps realtest exact.

import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalKit
@testable import opensky
import simd
import Testing
import UniformTypeIdentifiers

struct GrassRenderingAcceptanceRealDataTests {
    private static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
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

    private static let width = 640
    private static let height = 360
    private static let channelNoiseFloor = 4

    private struct Harness {
        let renderer: Renderer
        let weather: WeatherSystem
        let windyWeather: Weather
        let placementCount: Int
    }

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func whiterunGrassBatchesFadesAndMovesWithWeatherWind() throws {
        let harness = try makeHarness()
        harness.weather.forceWeather(harness.windyWeather.formID, transition: .instant)
        harness.renderer.timeOfDay = 13
        harness.renderer.grassWindScale = GrassRenderPolicy.maximumWindScale

        harness.renderer.grassEnabled = false
        let off = try frame(harness.renderer, time: 0)
        harness.renderer.grassEnabled = true
        let first = try frame(harness.renderer, time: 0)
        let fullStats = harness.renderer.lastGrassDrawStats
        let second = try frame(harness.renderer, time: 0.37)

        let visibleDelta = pixelDelta(off, first)
        let motionDelta = pixelDelta(first, second)
        #expect(visibleDelta > 25, "grass changed only \(visibleDelta) pixels")
        #expect(motionDelta > 10, "wind moved only \(motionDelta) pixels")
        #expect(harness.weather.currentWind.speed > 0)
        #expect(fullStats.sceneInstances >= harness.placementCount)
        #expect(fullStats.drawnInstances > 0)
        #expect(fullStats.drawCalls > 0)
        #expect(fullStats.drawCalls < fullStats.drawnInstances)
        #expect(fullStats.budgetDroppedInstances == 0)

        harness.renderer.grassDensityScale = 0.5
        _ = try frame(harness.renderer, time: 0.37)
        let densityStats = harness.renderer.lastGrassDrawStats
        #expect(densityStats.drawnInstances < fullStats.drawnInstances)
        #expect(densityStats.densityCulledInstances > 0)

        harness.renderer.grassDensityScale = 1
        harness.renderer.grassDrawDistance = GrassRenderPolicy.minimumDrawDistance
        _ = try frame(harness.renderer, time: 0.37)
        let distanceStats = harness.renderer.lastGrassDrawStats
        #expect(distanceStats.distanceCulledInstances > 0)

        let weatherName = harness.windyWeather.editorID ?? harness.windyWeather.formID.description
        let report = """
        [INFO] grass render acceptance: \(harness.placementCount) placements; \
        \(fullStats.sceneInstances) mesh instances; \(fullStats.drawnInstances) drawn in \
        \(fullStats.drawCalls) calls; \(fullStats.budgetDroppedInstances) budget-dropped
        [INFO] grass pixels: visible=\(visibleDelta), windy-motion=\(motionDelta); \
        weather=\(weatherName), wind=\(String(format: "%.3f", harness.weather.currentWind.speed))
        [INFO] grass controls: half-density drew \(densityStats.drawnInstances), culled \
        \(densityStats.densityCulledInstances); minimum-distance culled \
        \(distanceStats.distanceCulledInstances)
        """
        try writeEvidence(off: off, first: first, second: second, report: report)
    }

    @MainActor
    private func makeHarness() throws -> Harness {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let scene = try CellSceneBuilder(file: file, meshes: meshes, textures: textures)
            .buildScene(
                worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
                gridX: FirstRenderCell.gridX,
                gridY: FirstRenderCell.gridY
            )
        #expect(!scene.grassPlacements.isEmpty)
        #expect(!scene.renderScene.grass.isEmpty)
        let camera = try #require(Self.grassCamera(scene.grassPlacements))
        let weather = try #require(
            WeatherSystem(file: file, worldspaceEditorID: FirstRenderCell.worldspaceEditorID)
        )
        let windy = try #require(
            weather.store.selectableWeathers().max {
                ($0.data?.windSpeed ?? 0) < ($1.data?.windSpeed ?? 0)
            }
        )
        #expect((windy.data?.windSpeed ?? 0) > 0)
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(view: view, scene: scene.renderScene, camera: camera)
        renderer.weather = weather
        renderer.shadowQuality = .off
        return Harness(
            renderer: renderer,
            weather: weather,
            windyWeather: windy,
            placementCount: scene.grassPlacements.count
        )
    }

    private static func grassCamera(_ placements: [GrassPlacement]) -> SceneCamera? {
        guard !placements.isEmpty else { return nil }
        let radiusSquared: Float = 700 * 700
        let center = placements.max { lhs, rhs in
            let lhsCount = placements.count {
                simd_length_squared($0.position - lhs.position) < radiusSquared
            }
            let rhsCount = placements.count {
                simd_length_squared($0.position - rhs.position) < radiusSquared
            }
            return lhsCount < rhsCount
        }?.position
        guard let center else { return nil }
        let target = center + SIMD3<Float>(0, 0, 80)
        return SceneCamera(
            eye: target + SIMD3(-650, -650, 420),
            target: target,
            sunDirection: SceneCamera.demo.sunDirection,
            sunColor: SceneCamera.demo.sunColor,
            ambientColor: SceneCamera.demo.ambientColor
        )
    }

    @MainActor
    private func frame(_ renderer: Renderer, time: Float) throws -> [UInt8] {
        try Self.readPixels(renderer.renderOffscreen(
            width: Self.width, height: Self.height, animationTime: time
        ))
    }

    private func pixelDelta(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        stride(from: 0, to: min(lhs.count, rhs.count), by: 4).reduce(0) { count, pixel in
            let moved = (0 ..< 3).contains { channel in
                abs(Int(lhs[pixel + channel]) - Int(rhs[pixel + channel]))
                    > Self.channelNoiseFloor
            }
            return count + (moved ? 1 : 0)
        }
    }

    private static func readPixels(_ texture: MTLTexture) -> [UInt8] {
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

    private func writeEvidence(
        off: [UInt8], first: [UInt8], second: [UInt8], report: String
    ) throws {
        let logs = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for (name, pixels) in [("off", off), ("wind-a", first), ("wind-b", second)] {
            try writePNG(pixels, to: logs.appending(path: "grass-\(name).png"))
        }
        try report.write(
            to: logs.appending(path: "grass-rendering-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
        print(report)
    }

    private func writePNG(_ pixels: [UInt8], to url: URL) throws {
        var pixels = pixels
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &pixels,
            width: Self.width,
            height: Self.height,
            bitsPerComponent: 8,
            bytesPerRow: Self.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
