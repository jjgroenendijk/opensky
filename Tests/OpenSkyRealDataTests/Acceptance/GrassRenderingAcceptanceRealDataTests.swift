// GRAS render acceptance against the user's read-only Skyrim SE
// install. Renders cell-owned Whiterun grass through production batches,
// proves live density/distance policy + weather wind motion numerically, and
// writes only gitignored PNG/report evidence.

import CoreGraphics
import Foundation
import Metal
import MetalKit
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import simd
import Testing

@Suite(.tags(.acceptance, .gpu))
struct GrassRenderingAcceptanceRealDataTests {
    private static let width = 640
    private static let height = 360
    private static let channelNoiseFloor = 4

    private struct Harness {
        let renderer: Renderer
        let weather: WeatherSystem
        let windyWeather: Weather
        let placementCount: Int
    }

    @Test(.enabled(if: RealDataEnvironment.canRender))
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
        let install = try RealDataInstall.load()
        let scene = try install.sceneBuilder().buildFirstRenderCell()
        #expect(!scene.grassPlacements.isEmpty)
        #expect(!scene.renderScene.grass.isEmpty)
        let camera = try #require(Self.grassCamera(scene.grassPlacements))
        let weather = try #require(
            WeatherSystem(
                file: install.file,
                worldspaceEditorID: FirstRenderCell.worldspaceEditorID
            )
        )
        let windy = try #require(
            weather.store.selectableWeathers().max {
                ($0.data?.windSpeed ?? 0) < ($1.data?.windSpeed ?? 0)
            }
        )
        #expect((windy.data?.windSpeed ?? 0) > 0)
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
            device: install.device
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
        RenderedPixels.changedCount(lhs, rhs, tolerance: Self.channelNoiseFloor)
    }

    private static func readPixels(_ texture: MTLTexture) -> [UInt8] {
        RenderedPixels.read(texture)
    }

    private func writeEvidence(
        off: [UInt8], first: [UInt8], second: [UInt8], report: String
    ) throws {
        let logs = try RepositoryLogs.directory()
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for (name, pixels) in [("off", off), ("wind-a", first), ("wind-b", second)] {
            try RenderedPixels.writePNG(
                pixels,
                width: Self.width,
                height: Self.height,
                to: logs.appending(path: "grass-\(name).png")
            )
        }
        try report.write(
            to: logs.appending(path: "grass-rendering-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
        print(report)
    }
}
