// M8.4.3 HUD acceptance against the user's read-only Skyrim SE install.
// The walk-route farm door supplies real interaction metadata and collision;
// numeric A/B evidence plus rendered frames stay in ignored logs/.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct HUDAcceptanceRealDataTests {
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

    private static let width = 1280
    private static let height = 720

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func walkModeDoorPromptChangesRenderedPixels() throws {
        let root = try #require(Self.dataRoot)
        let device = try #require(Self.device)
        let fileSystem = VirtualFileSystem(root: root)
        let scene = try makeFarmScene(
            root: root,
            device: device,
            fileSystem: fileSystem
        )
        let target = try makeWalkTarget(scene: scene)
        let prompt = try #require(GameViewController.hudPrompt(for: target))
        #expect(target.interaction.reference == WalkPathRoute.farmDoor)
        #expect(target.interaction.action == .open)

        let renderer = try makeRenderer(device: device)
        let movie = try SWFMovieLoader(fileSystem: fileSystem).load(
            path: HUDMovieBridge.moviePath
        )
        try renderer.setSWFMovie(movie)
        let runtime = try #require(try renderer.startSWFRuntime())
        try HUDMovieBridge.validate(runtime: runtime)
        HUDMovieBridge.initialize(runtime: runtime, activationPrompt: nil)
        try assertAuthoredPlaceholderTextIsHidden(runtime)
        let hidden = try render(renderer)

        try renderer.updateSWFRuntime { runtime in
            HUDMovieBridge.setActivationPrompt(prompt, runtime: runtime)
        }
        let visible = try render(renderer)
        let changed = Self.changedPixels(hidden.pixels, visible.pixels)
        #expect(changed > 100, "live door prompt changed only \(changed) pixels")
        #expect(renderer.lastSWFDrawStats.skippedItems == 0)

        try FileManager.default.createDirectory(
            at: Self.logs,
            withIntermediateDirectories: true
        )
        try FrameScreenshot.write(
            texture: hidden.texture,
            to: Self.logs.appending(path: "hud-door-prompt-off.png")
        )
        try FrameScreenshot.write(
            texture: visible.texture,
            to: Self.logs.appending(path: "hud-door-prompt-on.png")
        )
        let report = """
        [INFO] walk-mode target: \(target.interaction.reference) \
        \(target.interaction.actionLabel) \(target.interaction.name)
        [INFO] target distance: \(target.distance)
        [INFO] live prompt: \(prompt)
        [INFO] prompt off/on changed pixels: \(changed)
        """
        try report.write(
            to: Self.logs.appending(path: "hud-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
        print(report)
    }

    private func assertAuthoredPlaceholderTextIsHidden(
        _ runtime: SWFMovieRuntime
    ) throws {
        for path in [
            "/HUDMovieBaseInstance/RolloverInfoInstance",
            "/HUDMovieBaseInstance/SubtitleTextHolder"
        ] {
            let node = try #require(runtime.node(atPath: path, from: runtime.root))
            #expect(!node.isVisible)
        }
    }

    private func makeFarmScene(
        root: GameDataRoot,
        device: MTLDevice,
        fileSystem: VirtualFileSystem
    ) throws -> CellScene {
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let textures = TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(
            fileSystem: fileSystem,
            device: device,
            textures: textures
        )
        return try CellSceneBuilder(
            file: file,
            meshes: meshes,
            textures: textures,
            fileSystem: fileSystem
        ).buildScene(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: WalkPathRoute.farmCell.x,
            gridY: WalkPathRoute.farmCell.y
        )
    }

    private func makeWalkTarget(scene: CellScene) throws -> InteractionTarget {
        let interaction = try #require(scene.interactions[WalkPathRoute.farmDoor])
        let shapes = scene.staticCollision.shapes.filter {
            $0.reference == WalkPathRoute.farmDoor
        }
        #expect(!shapes.isEmpty, "walk-route farm door has no collision")
        let hit = try #require(Self.raycastDoor(shapes))
        return InteractionTarget(
            interaction: interaction,
            hitPosition: hit.position,
            distance: hit.distance
        )
    }

    private static func raycastDoor(
        _ shapes: [StaticCollisionShape]
    ) -> InteractionRayHit? {
        for shape in shapes {
            let center = (shape.bounds.min + shape.bounds.max) / 2
            let extents = (shape.bounds.max - shape.bounds.min) / 2
            for axis in 0 ..< 3 {
                var offset = SIMD3<Float>(repeating: 0)
                offset[axis] = extents[axis] + 32
                for sign: Float in [-1, 1] {
                    let origin = center + offset * sign
                    guard
                        let ray = InteractionRay(origin: origin, direction: center - origin),
                        let hit = InteractionRaycaster.nearestHit(ray: ray, shapes: shapes)
                    else { continue }
                    return hit
                }
            }
        }
        return nil
    }

    @MainActor
    private func makeRenderer(device: MTLDevice) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view)
    }

    @MainActor
    private func render(_ renderer: Renderer) throws -> (texture: MTLTexture, pixels: [UInt8]) {
        let texture = try renderer.renderOffscreen(
            width: Self.width,
            height: Self.height,
            animationTime: 1
        )
        var pixels = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: Self.width * 4,
                from: MTLRegionMake2D(0, 0, Self.width, Self.height),
                mipmapLevel: 0
            )
        }
        return (texture, pixels)
    }

    private static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
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
}
