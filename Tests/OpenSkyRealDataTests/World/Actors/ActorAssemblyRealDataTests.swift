// Env-gated milestone 5.4 acceptance over the user's read-only Skyrim SE
// install. Resolves named Whiterun NPC Heimskr, assembles deterministic
// outfit + FaceGen assets at the ACHR pose, renders offscreen, writes only
// the resulting frame to gitignored logs/. CI skips without game data/Metal 4.

import CoreGraphics
import Foundation
import Metal
import MetalKit
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldTesting
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct ActorAssemblyRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func rendersHeimskrAtACHRWorldPose() throws {
        let device = try #require(RealDataEnvironment.device)
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let record = try #require(ESMWalk.record(withFormID: 0x0001_A682, in: file))
        let actor = try PlacedActor(record: record)
        #expect(actor.base == FormID(0x0001_3BAC))

        let appearance = try ActorTemplateResolver.build(from: file, localized: true)
            .resolve(base: actor.base)
        let resolver = ActorVisualResolver.build(
            from: file,
            localized: true,
            pluginName: "Skyrim.esm"
        )
        let visual = try resolver.resolve(appearance: appearance)

        let vfs = VirtualFileSystem(root: root)
        let textures = try TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let assembly = ActorAssembler(provider: meshes).assemble(
            placed: actor,
            visual: visual
        )

        let expectedPaths = [
            "clothes\\monk\\monkboots_1.nif",
            "clothes\\monk\\monkhood_1.nif",
            "clothes\\monk\\monkrobes_1.nif",
            "actors\\character\\character assets\\malehands_1.nif",
            "meshes\\actors\\character\\facegendata\\facegeom\\skyrim.esm\\00013bac.nif"
        ]
        #expect(assembly.isRenderable)
        #expect(assembly.models.map { $0.path.lowercased() } == expectedPaths)
        expectWornPartsAreInDrawOrder(visual, resolver: resolver)
        #expect(assembly.skips.allSatisfy { $0.reason == .appearance })
        #expect(assembly.transform.columns.3 == SIMD4(249.9946, -69.73085, 68, 1))
        #expect(abs(actor.scale - 1) < 1e-6)

        try renderAndCapture(assembly, device: device, minimumDraws: expectedPaths.count)
    }

    /// `ActorVisualResolver` sorts worn armatures by ARMA DNAM draw priority.
    /// `MonkBootsAA` and `MonkHoodAA` are 10 and `MonkRobesAA` is 15, so the hood
    /// comes before the robes, although `ClothesMonkRobesHooded` lists them the other way.
    private func expectWornPartsAreInDrawOrder(
        _ visual: ResolvedActorVisual,
        resolver: ActorVisualResolver
    ) {
        let priorities = visual.parts.compactMap { part -> UInt8? in
            guard case .outfit = part.origin else { return nil }
            return resolver.armorAddons[part.armature.rawValue]?.priority(female: false)
        }
        #expect(priorities == [10, 10, 15])
    }

    /// Renders the assembly offscreen and writes the frame to gitignored
    /// `logs/`. A rendered frame embeds the user's own assets, so it never
    /// leaves that directory (AGENTS.md "Legal & IP boundary").
    @MainActor
    private func renderAndCapture(
        _ assembly: ActorAssembly<ActorRenderAsset>,
        device: MTLDevice,
        minimumDraws: Int
    ) throws {
        let bounds = try #require(assembly.worldBounds)
        let scene = RenderScene(instances: assembly.renderPlacements)
        #expect(scene.drawCount > minimumDraws)
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
        let output = try logsDirectory.appending(path: "actor-heimskr.png")
        try FrameScreenshot.write(texture: texture, to: output)
        print("[INFO] Heimskr actor assembly frame: \(output.path)")
    }

    private func nonBackgroundFraction(texture: MTLTexture) -> Double {
        let pixels = RenderedPixels.read(texture)
        var lit = 0
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[pixel] > 8 || pixels[pixel + 1] > 8 || pixels[pixel + 2] > 8 {
                lit += 1
            }
        }
        return Double(lit) / Double(max(pixels.count / 4, 1))
    }

    private var logsDirectory: URL {
        get throws { try RepositoryLogs.directory() }
    }
}
