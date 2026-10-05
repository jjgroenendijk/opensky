// Precipitation acceptance against the user's read-only Skyrim SE
// install. Forces decoded clear/rain/snow presets through the live weather +
// renderer path, freezes a mid-rain cross-fade while particles keep playing,
// then resumes and transitions back to clear. Numeric evidence + local PNGs
// land only in gitignored .logs/.

import CoreGraphics
import Foundation
import Metal
import MetalKit
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import TagsTesting
import Testing

@Suite(.tags(.acceptance, .gpu))
struct PrecipitationAcceptanceRealDataTests {
    private static let width = 640
    private static let height = 360
    private static let channelNoiseFloor = 8
    private static let visibleDeltaThreshold = 250

    private struct Harness {
        let renderer: Renderer
        let weather: WeatherSystem
        let clear: FormID
        let rain: FormID
        let snow: FormID
    }

    private struct EvidenceFrames {
        let clear: [UInt8]
        let pausedRain: [UInt8]
        let rain: [UInt8]
        let snow: [UInt8]
        let returnedClear: [UInt8]
    }

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func rainSnowPauseAndClearProduceVisibleFrames() throws {
        let harness = try makeHarness()
        let clear = try settle(harness, on: harness.clear, particleFrames: 1)
        let pausedRain = try pauseMidRain(harness)
        let rain = try settle(harness, on: harness.rain, particleFrames: 35)
        let snow = try settle(harness, on: harness.snow, particleFrames: 80)
        let returnedClear = try returnToClear(harness)

        let clearRain = pixelDelta(clear, rain)
        let clearSnow = pixelDelta(clear, snow)
        let rainSnow = pixelDelta(rain, snow)
        let rainReturnedClear = pixelDelta(rain, returnedClear)
        for (label, delta) in [
            ("clear/rain", clearRain), ("clear/snow", clearSnow),
            ("rain/snow", rainSnow), ("rain/returned-clear", rainReturnedClear)
        ] {
            #expect(delta > Self.visibleDeltaThreshold, "\(label) changed only \(delta) px")
        }

        try writeEvidence(
            EvidenceFrames(
                clear: clear,
                pausedRain: pausedRain,
                rain: rain,
                snow: snow,
                returnedClear: returnedClear
            ),
            report: """
            [INFO] precipitation frame deltas (px): clear/rain=\(clearRain) \
            clear/snow=\(clearSnow) rain/snow=\(rainSnow) \
            rain/returned-clear=\(rainReturnedClear)
            """
        )
    }

    @MainActor
    private func pauseMidRain(_ harness: Harness) throws -> [UInt8] {
        harness.weather.forceWeather(harness.clear, transition: .instant)
        harness.weather.update(deltaTime: 0, hour: 13)
        harness.weather.forceWeather(harness.rain, transition: .timed)
        while harness.weather.transitionFraction < 0.35 {
            harness.weather.update(deltaTime: 0.1, hour: 13)
        }
        harness.weather.transitionsPaused = true
        let fraction = harness.weather.transitionFraction
        let pixels = try renderFrames(harness.renderer, count: 35)
        #expect(harness.weather.transitionFraction == fraction)
        #expect(harness.renderer.precipitation.snapshot.rainLiveCount > 0)
        #expect(harness.renderer.precipitation.snapshot.state.rainIntensity > 0)
        return pixels
    }

    @MainActor
    private func settle(
        _ harness: Harness,
        on weather: FormID,
        particleFrames: Int
    ) throws -> [UInt8] {
        harness.weather.transitionsPaused = false
        harness.weather.forceWeather(weather, transition: .timed)
        harness.weather.update(deltaTime: 100, hour: 13)
        #expect(harness.weather.transitionFraction == 1)
        return try renderFrames(harness.renderer, count: particleFrames)
    }

    @MainActor
    private func returnToClear(_ harness: Harness) throws -> [UInt8] {
        harness.weather.forceWeather(harness.clear, transition: .timed)
        #expect(harness.weather.transitionFraction == 0)
        harness.weather.update(deltaTime: 100, hour: 13)
        #expect(harness.weather.transitionFraction == 1)
        let pixels = try renderFrames(harness.renderer, count: 130)
        let snapshot = harness.renderer.precipitation.snapshot
        #expect(snapshot.state == .none)
        #expect(snapshot.rainLiveCount == 0)
        #expect(snapshot.snowLiveCount == 0)
        return pixels
    }

    @MainActor
    private func renderFrames(_ renderer: Renderer, count: Int) throws -> [UInt8] {
        var pixels: [UInt8] = []
        for _ in 0 ..< count {
            pixels = try Self.readPixels(
                renderer.renderOffscreen(width: Self.width, height: Self.height)
            )
        }
        return pixels
    }

    @MainActor
    private func makeHarness() throws -> Harness {
        let install = try RealDataInstall.load()
        let scene = try install.sceneBuilder().buildFirstRenderCell()
        let bounds = try #require(scene.bounds)
        let weather = try #require(
            WeatherSystem(
                file: install.file,
                worldspaceEditorID: FirstRenderCell.worldspaceEditorID
            )
        )
        func preset(_ value: WeatherPreset) throws -> FormID {
            try #require(weather.store.weather(for: value)?.formID)
        }
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
            device: install.device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view, scene: scene.renderScene, camera: SceneCamera.framing(bounds: bounds)
        )
        renderer.weather = weather
        renderer.timeOfDay = 13
        return try Harness(
            renderer: renderer,
            weather: weather,
            clear: preset(.clear),
            rain: preset(.rain),
            snow: preset(.snow)
        )
    }

    private func pixelDelta(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        RenderedPixels.changedCount(lhs, rhs, tolerance: Self.channelNoiseFloor)
    }

    private static func readPixels(_ texture: MTLTexture) -> [UInt8] {
        RenderedPixels.read(texture)
    }

    private func writeEvidence(_ frames: EvidenceFrames, report: String) throws {
        let logs = try RepositoryLogs.directory()
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for (name, pixels) in [
            ("clear", frames.clear), ("paused-rain", frames.pausedRain),
            ("rain", frames.rain), ("snow", frames.snow),
            ("returned-clear", frames.returnedClear)
        ] {
            try RenderedPixels.writePNG(
                pixels,
                width: Self.width,
                height: Self.height,
                to: logs.appending(path: "precipitation-\(name).png")
            )
        }
        try report.write(
            to: logs.appending(path: "precipitation-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
        print(report)
    }
}
