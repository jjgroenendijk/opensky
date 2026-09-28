// Env-gated lip-sync render evidence over a real archive track and a real
// actor face. Six PNGs and a numeric report remain under gitignored `logs/`.

import CoreGraphics
import Foundation
import Metal
import MetalKit
@testable import OpenSkyEngine
@testable import OpenSkyFormats
@testable import OpenSkyGameData
import simd
import Testing

struct LipSyncRenderRealDataTests {
    private static let voicePath =
        "sound\\voice\\skyrim.esm\\maleeventoned\\wigreeting__000c7917_1.fuz"
    private static let sampleTimes: [Double] = [0.30, 11.0 / 30.0, 0.50]
    private static let device = MTLCreateSystemDefaultDevice()
    private static let dataRoot: GameDataRoot? = {
        guard ProcessInfo.processInfo.environment[GameDataLocator.environmentKey] != nil
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        device?.supportsFamily(.metal4) == true && dataRoot != nil
    }

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func threeTrackTimesChangeFacePixelsAndRepeatExactly() throws {
        let harness = try makeHarness()
        var deltas: [Int] = []
        for (index, time) in Self.sampleTimes.enumerated() {
            harness.clock.publish(time)
            harness.lip.isEnabled = false
            let off = try frame(
                harness.renderer,
                time: Float(time),
                name: "lip-\(index)-off.png"
            )
            harness.lip.isEnabled = true
            let on = try frame(
                harness.renderer,
                time: Float(time),
                name: "lip-\(index)-on.png"
            )
            let repeated = try frame(harness.renderer, time: Float(time), name: nil)
            let delta = RenderedPixels.changedCount(off, on)
            deltas.append(delta)
            #expect(delta > 20, "lip sync at \(time)s changed only \(delta) pixels")
            #expect(
                RenderedPixels.changedCount(on, repeated) == 0,
                "\(time)s was not deterministic"
            )
        }
        let captures = try runDirectory.path()
        print(
            "[INFO] lip render A/B: \(Self.voicePath), times \(Self.sampleTimes), "
                + "changed pixels \(deltas), captures \(captures)"
        )
    }

    @MainActor
    private func makeHarness() throws -> LipRenderHarness {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let vfs = VirtualFileSystem(root: root)
        try #require(vfs.exists(Self.voicePath))
        let lipData = try #require(
            FUZFile(data: vfs.contents(forPath: Self.voicePath)).lipData
        )
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let builder = CellSceneBuilder(
            file: file, meshes: meshes, textures: textures, fileSystem: vfs
        )
        let placed = try PlacedActor(record: #require(
            ESMWalk.record(withFormID: 0x0001_A682, in: file)
        ))
        let resolvers = builder.actorResolversBuildingIfNeeded(localized: true)
        let appearance = try resolvers.template.resolve(base: placed.base)
        let visual = try resolvers.visual.resolve(appearance: appearance)
        let assembly = ActorAssembler(provider: meshes).assemble(placed: placed, visual: visual)
        let face = try #require(builder.makeFaceMorphPlayback(assembly: assembly))
        let lip = LipSyncPlayback(faceMorph: face)
        let clock = VoicePlaybackClock()
        try lip.start(
            track: LIPFile(data: lipData),
            clock: clock,
            line: Self.voicePath,
            animationTime: 0
        )
        let scene = RenderScene(
            instances: assembly.renderPlacements(
                at: assembly.transform, faceMorphs: face.bindings
            ),
            animations: [face, lip]
        )
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 800), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: scene,
            camera: faceCamera(assembly: assembly)
        )
        return LipRenderHarness(renderer: renderer, lip: lip, clock: clock)
    }

    private func faceCamera(assembly: ActorAssembly<ActorRenderAsset>) -> SceneCamera {
        let origin = SIMD3(
            assembly.transform.columns.3.x,
            assembly.transform.columns.3.y,
            assembly.transform.columns.3.z
        )
        let head = origin + SIMD3<Float>(0, 0, 112)
        let direction = simd_normalize(SIMD3<Float>(-1, -1, 0.25))
        return SceneCamera(
            eye: head + direction * 160,
            target: head,
            sunDirection: SceneCamera.demo.sunDirection,
            sunColor: SceneCamera.demo.sunColor,
            ambientColor: SceneCamera.demo.ambientColor
        )
    }

    @MainActor
    private func frame(_ renderer: Renderer, time: Float, name: String?) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(
            width: 800, height: 800, animationTime: time
        )
        if let name {
            try FrameScreenshot.write(texture: texture, to: runDirectory.appending(path: name))
        }
        return RenderedPixels.read(texture)
    }

    private var runDirectory: URL {
        get throws { try RepositoryLogs.directory("test-fast/latest") }
    }
}

@MainActor
private struct LipRenderHarness {
    let renderer: Renderer
    let lip: LipSyncPlayback
    let clock: VoicePlaybackClock
}
