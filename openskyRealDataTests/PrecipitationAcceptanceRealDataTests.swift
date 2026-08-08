// M7.4.2 precipitation acceptance against the user's read-only Skyrim SE
// install. Forces decoded clear/rain/snow presets through the live weather +
// renderer path, freezes a mid-rain cross-fade while particles keep playing,
// then resumes and transitions back to clear. Numeric evidence + local PNGs
// land only in gitignored logs/. One @Test keeps tools/realtest.sh's gate.

import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalKit
@testable import opensky
import Testing
import UniformTypeIdentifiers

struct PrecipitationAcceptanceRealDataTests {
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

    @Test(.enabled(if: Self.canRun))
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
        let bounds = try #require(scene.bounds)
        let weather = try #require(
            WeatherSystem(file: file, worldspaceEditorID: FirstRenderCell.worldspaceEditorID)
        )
        func preset(_ value: WeatherPreset) throws -> FormID {
            try #require(weather.store.weather(for: value)?.formID)
        }
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height), device: device
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

    private func writeEvidence(_ frames: EvidenceFrames, report: String) throws {
        let logs = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for (name, pixels) in [
            ("clear", frames.clear), ("paused-rain", frames.pausedRain),
            ("rain", frames.rain), ("snow", frames.snow),
            ("returned-clear", frames.returnedClear)
        ] {
            try writePNG(pixels, to: logs.appending(path: "precipitation-\(name).png"))
        }
        try report.write(
            to: logs.appending(path: "precipitation-acceptance.log"),
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
