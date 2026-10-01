// Weather acceptance on the real install, over the `FirstRenderCell` scene:
// clear, cloudy, and fog draw different frames, a clear-to-cloudy transition
// moves steadily, and 04:00 differs from 13:00. One `@Test`, because
// `tools/realtest.sh` runs exactly one test. Numbers go to `logs/`.

import Foundation
import Metal
import MetalKit
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import TagsTesting
import Testing

@Suite(.tags(.acceptance, .gpu))
struct WeatherAcceptanceRealDataTests {
    private static let width = 1280
    private static let height = 720
    /// A pixel counts as changed when any RGB channel moves more than this many
    /// 8-bit levels — above sRGB rounding noise, below a real repaint.
    private static let channelNoiseFloor = 8
    /// Minimum changed pixels for two frames to count as visibly distinct.
    private static let distinctThreshold = 1000

    /// The live renderer + weather runtime plus the three resolved vanilla
    /// weather FormIDs, built once for the whole acceptance sweep.
    private struct Harness {
        let renderer: Renderer
        let weather: WeatherSystem
        let clear: FormID
        let cloudy: FormID
        let fog: FormID
    }

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func forcedWeathersTransitionsAndTimeProduceDistinctFrames() throws {
        let harness = try makeHarness()
        var report: [String] = []
        try report.append(distinctLookEvidence(harness))
        try report.append(transitionEvidence(harness))
        try report.append(timeOfDayEvidence(harness))
        try writeReport(report)
    }

    // MARK: - Evidence phases

    /// Three weathers forced instant at 13:00 must paint pairwise-different
    /// frames (sky palette + fog + ambient repaint).
    @MainActor
    private func distinctLookEvidence(_ harness: Harness) throws -> String {
        let clearFrame = try frame(harness, force: harness.clear, hour: 13)
        let cloudyFrame = try frame(harness, force: harness.cloudy, hour: 13)
        let fogFrame = try frame(harness, force: harness.fog, hour: 13)
        let clearVsCloudy = pixelDelta(clearFrame, cloudyFrame)
        let clearVsFog = pixelDelta(clearFrame, fogFrame)
        let cloudyVsFog = pixelDelta(cloudyFrame, fogFrame)
        #expect(clearVsCloudy > Self.distinctThreshold, "SkyrimClear ~= SkyrimCloudy")
        #expect(clearVsFog > Self.distinctThreshold, "SkyrimClear ~= SkyrimFog")
        #expect(cloudyVsFog > Self.distinctThreshold, "SkyrimCloudy ~= SkyrimFog")
        return "[INFO] pairwise weather deltas (px): clear/cloudy=\(clearVsCloudy) "
            + "clear/fog=\(clearVsFog) cloudy/fog=\(cloudyVsFog)"
    }

    /// Settle on clear, force cloudy timed, step deterministically to mid-blend
    /// (proving progress climbs monotonically), and render a frame that differs
    /// from both endpoints.
    @MainActor
    private func transitionEvidence(_ harness: Harness) throws -> String {
        let weather = harness.weather
        let clearFrame = try frame(harness, force: harness.clear, hour: 13)
        let cloudyFrame = try frame(harness, force: harness.cloudy, hour: 13)
        weather.forceWeather(harness.clear, transition: .instant)
        weather.update(deltaTime: 0, hour: 13)
        weather.forceWeather(harness.cloudy, transition: .timed)
        var fractions: [Float] = []
        var steps = 0
        while weather.transitionFraction < 0.45, steps < 100_000 {
            weather.update(deltaTime: 0.1, hour: 13)
            fractions.append(weather.transitionFraction)
            steps += 1
        }
        let monotonic = zip(fractions, fractions.dropFirst()).allSatisfy { $0 < $1 }
        #expect(monotonic, "transition progress not monotonic: \(fractions)")
        #expect((fractions.last ?? 0) > 0.4, "transition never reached mid-blend")
        let midFrame = try readPixels(
            harness.renderer.renderOffscreen(width: Self.width, height: Self.height)
        )
        let midVsClear = pixelDelta(midFrame, clearFrame)
        let midVsCloudy = pixelDelta(midFrame, cloudyFrame)
        #expect(midVsClear > Self.distinctThreshold, "mid-frame matched clear endpoint")
        #expect(midVsCloudy > Self.distinctThreshold, "mid-frame matched cloudy endpoint")
        return "[INFO] transition mid-frame deltas (px): vs clear=\(midVsClear) "
            + "vs cloudy=\(midVsCloudy); progress samples=\(fractions.count) "
            + "last=\(String(format: "%.2f", fractions.last ?? 0))"
    }

    /// The same weather at 04:00 vs 13:00 must differ (time-of-day blend).
    @MainActor
    private func timeOfDayEvidence(_ harness: Harness) throws -> String {
        let night = try frame(harness, force: harness.clear, hour: 4)
        let day = try frame(harness, force: harness.clear, hour: 13)
        let delta = pixelDelta(night, day)
        #expect(delta > Self.distinctThreshold, "SkyrimClear identical at 04:00 and 13:00")
        return "[INFO] time-of-day delta (px): SkyrimClear 04:00 vs 13:00=\(delta)"
    }

    // MARK: - Setup

    @MainActor
    private func makeHarness() throws -> Harness {
        let install = try RealDataInstall.load()
        let cellScene = try install.sceneBuilder().buildFirstRenderCell()
        #expect(cellScene.renderScene.sky != nil, "exterior scene must draw a sky for weather")
        let bounds = try #require(cellScene.bounds, "no world bounds — nothing drew")
        let weather = try #require(
            WeatherSystem(
                file: install.file,
                worldspaceEditorID: FirstRenderCell.worldspaceEditorID
            ),
            "Skyrim.esm carries no weather data"
        )
        let selectable = weather.store.selectableWeathers()
        func formID(_ editorID: String) throws -> FormID {
            try #require(
                selectable.first { $0.editorID == editorID }?.formID,
                "vanilla weather \(editorID) not found in Skyrim.esm"
            )
        }
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
            device: install.device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view, scene: cellScene.renderScene, camera: SceneCamera.framing(bounds: bounds)
        )
        renderer.weather = weather
        return try Harness(
            renderer: renderer, weather: weather,
            clear: formID("SkyrimClear"),
            cloudy: formID("SkyrimCloudy"),
            fog: formID("SkyrimFog")
        )
    }

    // MARK: - Render + compare

    /// Forces `id` instantly at `hour` and returns the rendered pixels. Forced
    /// weather + a fixed hour is deterministic: reroll is off and no game-hours
    /// accumulate.
    @MainActor
    private func frame(_ harness: Harness, force id: FormID, hour: Float) throws -> [UInt8] {
        harness.renderer.timeOfDay = hour
        harness.weather.forceWeather(id, transition: .instant)
        return try readPixels(
            harness.renderer.renderOffscreen(width: Self.width, height: Self.height)
        )
    }

    /// Count of pixels whose color moved past the channel noise floor.
    private func pixelDelta(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        RenderedPixels.changedCount(lhs, rhs, tolerance: Self.channelNoiseFloor)
    }

    @MainActor
    private func readPixels(_ texture: MTLTexture) -> [UInt8] {
        RenderedPixels.read(texture)
    }

    private func writeReport(_ lines: [String]) throws {
        let output = lines.joined(separator: "\n")
        let logsDirectory = try RepositoryLogs.directory()
        try FileManager.default.createDirectory(
            at: logsDirectory, withIntermediateDirectories: true
        )
        try output.write(
            to: logsDirectory.appending(path: "weather-acceptance.log"),
            atomically: true, encoding: .utf8
        )
        print(output)
    }
}
