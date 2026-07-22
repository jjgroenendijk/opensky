// M7.6 integrated acceptance against user's read-only Skyrim SE install.
// One exterior combines actors, shadows, forced rain, world particles,
// precipitation, and grass; Chillfurrow Farm interior combines animation +
// its applicable fire effect. Numeric A/B deltas + PNGs stay in ignored logs/.

import Foundation
import Metal
import MetalKit
@testable import opensky
import Testing

struct LivingEnvironmentAcceptanceRealDataTests {
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

    private static let size = (width: 640, height: 360)

    private struct Frame {
        let texture: MTLTexture
        let pixels: [UInt8]
    }

    private struct ExteriorDeltas {
        let animation: Int
        let shadow: Int
        let weather: Int
        let particles: Int
        let precipitation: Int
        let grass: Int
        let combined: Int
        let allOff: Frame
    }

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func exteriorAndInteriorRunEveryApplicableSystem() throws {
        let harness = try makeHarness()
        let exterior = try harness.builder.buildScene(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: WalkPathRoute.farmCell.x,
            gridY: WalkPathRoute.farmCell.y
        )
        let exteriorEvidence = try verifyExterior(exterior, weather: harness.weather)

        let interior = try harness.builder.buildInteriorScene(
            cellFormID: WalkPathRoute.farmInterior
        )
        let interiorEvidence = try verifyInterior(interior)
        let report = exteriorEvidence + "\n" + interiorEvidence
        try report.write(
            to: Self.logs.appending(path: "living-environment-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
        print(report)
    }

    @MainActor
    private func verifyExterior(_ scene: CellScene, weather: WeatherSystem) throws -> String {
        #expect(scene.summary.actorAnimatedCount > 0)
        #expect(!scene.renderScene.animations.isEmpty)
        #expect(!scene.renderScene.particles.isEmpty)
        #expect(!scene.renderScene.grass.isEmpty)
        #expect(scene.renderScene.sky != nil)
        let rain = try #require(weather.store.weather(for: .rain))
        weather.forceWeather(rain.formID, transition: .instant)
        let renderer = try makeRenderer(scene: scene)
        renderer.weather = weather
        renderer.timeOfDay = 13
        renderer.updateWeather(deltaTime: 0)
        renderer.seekParticles(to: 1.25)
        for _ in 0 ..< 45 {
            renderer.updatePrecipitation(deltaTime: 1 / 30)
        }
        let allOn = try frame(renderer, time: 1.25)
        let precipitation = renderer.precipitation.snapshot
        let shadow = renderer.lastShadowDrawStats
        let grass = renderer.lastGrassDrawStats
        #expect(renderer.lastAnimationUpdatedBoneCount > 0)
        #expect(scene.renderScene.particles.reduce(0) { $0 + $1.liveCount } > 0)
        #expect(precipitation.rainLiveCount > 0)
        #expect(shadow.drawnInstances > 0)
        #expect(grass.drawnInstances > 0)

        let deltas = try exteriorDeltas(renderer, baseline: allOn.pixels)
        #expect(deltas.combined > 250)
        try Self.write(allOn.texture, name: "living-exterior-all-on.png")
        try Self.write(deltas.allOff.texture, name: "living-exterior-all-off.png")
        return """
        [INFO] living exterior (7,-3): \(scene.summary.actorAnimatedCount) animated actors, \
        \(scene.renderScene.particles.count) particle systems, \
        \(scene.grassPlacements.count) grass placements
        [INFO] live exterior: \(renderer.lastAnimationUpdatedBoneCount) bind-pose bones after \
        A/B, \(precipitation.rainLiveCount) rain, \(shadow.drawnInstances) shadow casters, \
        \(grass.drawnInstances) grass instances
        [INFO] A/B changed pixels: animation=\(deltas.animation), shadows=\(deltas.shadow), \
        weather=\(deltas.weather), particles=\(deltas.particles), \
        precipitation=\(deltas.precipitation), grass=\(deltas.grass), \
        all-on/all-off=\(deltas.combined)
        """
    }

    @MainActor
    private func exteriorDeltas(
        _ renderer: Renderer,
        baseline: [UInt8]
    ) throws -> ExteriorDeltas {
        let animation = try toggledDelta(renderer, baseline: baseline, time: 1.25) {
            renderer.actorAnimationsEnabled = false
        } restore: { renderer.actorAnimationsEnabled = true }
        let shadow = try toggledDelta(renderer, baseline: baseline, time: 1.25) {
            renderer.shadowQuality = .off
        } restore: { renderer.shadowQuality = .high }
        let weather = try toggledDelta(renderer, baseline: baseline, time: 1.25) {
            renderer.weatherEnabled = false
        } restore: { renderer.weatherEnabled = true }
        let particles = try toggledDelta(renderer, baseline: baseline, time: 1.25) {
            renderer.particlesEnabled = false
        } restore: { renderer.particlesEnabled = true }
        let precipitation = try toggledDelta(renderer, baseline: baseline, time: 1.25) {
            renderer.precipitationEnabled = false
        } restore: { renderer.precipitationEnabled = true }
        let grass = try toggledDelta(renderer, baseline: baseline, time: 1.25) {
            renderer.grassEnabled = false
        } restore: { renderer.grassEnabled = true }
        renderer.actorAnimationsEnabled = false
        renderer.shadowQuality = .off
        renderer.weatherEnabled = false
        renderer.particlesEnabled = false
        renderer.precipitationEnabled = false
        renderer.grassEnabled = false
        let allOff = try frame(renderer, time: 1.25)
        return ExteriorDeltas(
            animation: animation,
            shadow: shadow,
            weather: weather,
            particles: particles,
            precipitation: precipitation,
            grass: grass,
            combined: Self.pixelDelta(baseline, allOff.pixels),
            allOff: allOff
        )
    }

    @MainActor
    private func verifyInterior(_ scene: CellScene) throws -> String {
        #expect(scene.summary.actorAnimatedCount > 0)
        #expect(!scene.renderScene.animations.isEmpty)
        #expect(!scene.renderScene.particles.isEmpty)
        let renderer = try makeRenderer(scene: scene)
        let first = try frame(renderer, time: 0.5)
        let second = try frame(renderer, time: 1.0)
        let changed = Self.pixelDelta(first.pixels, second.pixels)
        let live = scene.renderScene.particles.reduce(0) { $0 + $1.liveCount }
        #expect(renderer.lastAnimationUpdatedBoneCount > 0)
        #expect(live > 0)
        #expect(renderer.precipitation.snapshot.state == .none)
        #expect(changed > 0)
        try Self.write(first.texture, name: "living-interior-a.png")
        try Self.write(second.texture, name: "living-interior-b.png")
        return "[INFO] living interior 00016204: \(scene.summary.actorAnimatedCount) animated "
            + "actor, \(scene.renderScene.particles.count) particle system, \(live) live; "
            + "exact-time changed pixels=\(changed); no precipitation"
    }

    @MainActor
    private func makeRenderer(scene: CellScene) throws -> Renderer {
        let device = try #require(Self.device)
        let bounds = try #require(scene.bounds)
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.size.width, height: Self.size.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(
            view: view,
            scene: scene.renderScene,
            camera: SceneCamera.framing(bounds: bounds)
        )
    }

    @MainActor
    private func frame(_ renderer: Renderer, time: Float) throws -> Frame {
        let texture = try renderer.renderOffscreen(
            width: Self.size.width,
            height: Self.size.height,
            animationTime: time
        )
        return Frame(texture: texture, pixels: Self.read(texture))
    }

    @MainActor
    private func toggledDelta(
        _ renderer: Renderer,
        baseline: [UInt8],
        time: Float,
        toggle: () -> Void,
        restore: () -> Void
    ) throws -> Int {
        toggle()
        let pixels = try frame(renderer, time: time).pixels
        restore()
        return Self.pixelDelta(baseline, pixels)
    }

    private func makeHarness() throws -> (builder: CellSceneBuilder, weather: WeatherSystem) {
        let root = try #require(Self.dataRoot)
        let device = try #require(Self.device)
        let fileSystem = VirtualFileSystem(root: root)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let textures = TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        let builder = CellSceneBuilder(
            file: file,
            meshes: meshes,
            textures: textures,
            fileSystem: fileSystem
        )
        let weather = try #require(
            WeatherSystem(file: file, worldspaceEditorID: FirstRenderCell.worldspaceEditorID)
        )
        return (builder, weather)
    }

    private static func read(_ texture: MTLTexture) -> [UInt8] {
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

    private static func pixelDelta(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        stride(from: 0, to: min(lhs.count, rhs.count), by: 4).reduce(0) { count, index in
            let changed = (0 ..< 3).contains {
                abs(Int(lhs[index + $0]) - Int(rhs[index + $0])) > 8
            }
            return count + (changed ? 1 : 0)
        }
    }

    private static var logs: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "logs")
    }

    private static func write(_ texture: MTLTexture, name: String) throws {
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FrameScreenshot.write(texture: texture, to: logs.appending(path: name))
    }
}
