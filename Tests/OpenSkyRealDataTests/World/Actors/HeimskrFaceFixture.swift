import CoreGraphics
import Metal
import MetalKit
@testable import OpenSkyAudio
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyFormatsAudio
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

/// Heimskr's head from the install, with its face-morph playback, for the face renders.
struct HeimskrFace {
    /// A vanilla greeting whose lip track moves Heimskr's mouth.
    static let voicePath =
        "sound\\voice\\skyrim.esm\\maleeventoned\\wigreeting__000c7917_1.fuz"
    static let size = 800

    let device: any MTLDevice
    let fileSystem: VirtualFileSystem
    let assembly: ActorAssembly<ActorRenderAsset>
    let playback: FaceMorphPlayback

    static func load() throws -> Self {
        let install = try RealDataInstall.load()
        let builder = install.sceneBuilder(readsLooseFiles: true)
        let placed = try PlacedActor(record: #require(
            ESMWalk.record(withFormID: 0x0001_A682, in: install.file)
        ))
        let resolvers = builder.actorResolversBuildingIfNeeded()
        let appearance = try resolvers.template.resolve(base: placed.base)
        let visual = try resolvers.visual.resolve(appearance: appearance)
        let assembly = ActorAssembler(provider: install.meshes)
            .assemble(placed: placed, visual: visual)
        return try Self(
            device: install.device,
            fileSystem: install.fileSystem,
            assembly: assembly,
            playback: #require(builder.makeFaceMorphPlayback(assembly: assembly))
        )
    }

    /// The face with the `voicePath` lip track started at time zero on a fresh clock.
    @MainActor
    static func lipSyncHarness() throws -> LipSyncFaceHarness {
        let face = try load()
        try #require(face.fileSystem.exists(voicePath))
        let lipData = try #require(
            FUZFile(data: face.fileSystem.contents(forPath: voicePath)).lipData
        )
        let lip = LipSyncPlayback(faceMorph: face.playback)
        let clock = VoicePlaybackClock()
        try lip.start(
            track: LIPFile(data: lipData),
            clock: clock,
            line: voicePath,
            animationTime: 0
        )
        return try LipSyncFaceHarness(
            renderer: face.renderer(animations: [face.playback, lip]),
            lip: lip,
            clock: clock
        )
    }

    /// A paused offscreen renderer looking at the head from in front and slightly above.
    @MainActor
    func renderer(animations: [any RenderAnimation]) throws -> Renderer {
        try Self.renderer(
            placements: assembly.renderPlacements(
                at: assembly.transform, faceMorphs: playback.bindings
            ),
            animations: animations,
            transform: assembly.transform,
            device: device
        )
    }

    /// The same view of any placements around an actor at `transform`.
    @MainActor
    static func renderer(
        placements: [RenderPlacement],
        animations: [any RenderAnimation],
        transform: float4x4,
        device: any MTLDevice
    ) throws -> Renderer {
        let scene = RenderScene(instances: placements, animations: animations)
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: size, height: size), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view, scene: scene, camera: camera(transform: transform))
    }

    private static func camera(transform: float4x4) -> SceneCamera {
        let origin = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
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
}

@MainActor
struct LipSyncFaceHarness {
    let renderer: Renderer
    let lip: LipSyncPlayback
    let clock: VoicePlaybackClock
}
