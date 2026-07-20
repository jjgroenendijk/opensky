// Env-gated milestone 5.4 acceptance over the user's read-only Skyrim SE
// install. Resolves named Whiterun NPC Heimskr, assembles deterministic
// outfit + FaceGen assets at the ACHR pose, renders offscreen, writes only
// the resulting frame to gitignored logs/. CI skips without game data/Metal 4.

import CoreGraphics
import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct ActorAssemblyRealDataTests {
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
    func rendersHeimskrAtACHRWorldPose() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let record = try #require(ESMWalk.record(withFormID: 0x0001_A682, in: file))
        let actor = try PlacedActor(record: record)
        #expect(actor.base == FormID(0x0001_3BAC))

        let appearance = try ActorTemplateResolver.build(from: file, localized: true)
            .resolve(base: actor.base)
        let visual = try ActorVisualResolver.build(
            from: file,
            localized: true,
            pluginName: "Skyrim.esm"
        ).resolve(appearance: appearance)

        let vfs = VirtualFileSystem(root: root)
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let assembly = ActorAssembler(provider: meshes).assemble(
            placed: actor,
            visual: visual
        )

        let expectedPaths = [
            "clothes\\monk\\monkboots_1.nif",
            "clothes\\monk\\monkrobes_1.nif",
            "clothes\\monk\\monkhood_1.nif",
            "actors\\character\\character assets\\malehands_1.nif",
            "meshes\\actors\\character\\facegendata\\facegeom\\skyrim.esm\\00013bac.nif"
        ]
        #expect(assembly.isRenderable)
        #expect(assembly.models.map { $0.path.lowercased() } == expectedPaths)
        #expect(assembly.skips.allSatisfy { $0.reason == .appearance })
        #expect(assembly.transform.columns.3 == SIMD4(249.9946, -69.73085, 68, 1))
        #expect(abs(actor.scale - 1) < 1e-6)

        let bounds = try #require(assembly.worldBounds)
        let scene = RenderScene(instances: assembly.renderPlacements)
        #expect(scene.drawCount > expectedPaths.count)
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 800),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: scene,
            camera: SceneCamera.framing(bounds: (bounds.min, bounds.max))
        )
        let texture = try renderer.renderOffscreen(width: 800, height: 800)
        #expect(nonBackgroundFraction(texture: texture) > 0.01)

        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        let output = logsDirectory.appending(path: "actor-heimskr.png")
        try FrameScreenshot.write(texture: texture, to: output)
        print("[INFO] Heimskr actor assembly frame: \(output.path)")
    }

    private func nonBackgroundFraction(texture: MTLTexture) -> Double {
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
        var lit = 0
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[pixel] > 8 || pixels[pixel + 1] > 8 || pixels[pixel + 2] > 8 {
                lit += 1
            }
        }
        return Double(lit) / Double(max(pixels.count / 4, 1))
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
    }
}
