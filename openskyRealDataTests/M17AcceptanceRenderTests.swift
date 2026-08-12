// M17 acceptance, pixel half (issue #209): the milestone's two visible claims
// measured as changed-pixel counts rather than eyeballed — the speaker's mouth
// moves with the audio clock, and a conversation takes the view and puts the
// menu over it.
//
// The mouth is measured in a region rather than over the whole frame, which is
// what makes the claim "the mouth moved" instead of "something moved". The
// region is the middle of the head shot the harness frames, and the assertion is
// twofold: pixels changed inside it, and most of the frame's change is inside
// it. A morph that moved a shoulder would pass the first and fail the second.
//
// The camera-and-menu half runs both toggles over one real cell in one run, in
// the order a conversation applies them: the view moves to frame the speaker,
// then the vanilla movie is brought up on top. `DialogueCameraRenderRealDataTests`
// and `DialogueMenuRealDataTests` each prove their own toggle; what this adds is
// that the two compose, which is the only frame a player ever actually sees.
//
// Gated on a Metal 4 device *and* on the install, because what is drawn is the
// user's own art. Rendered frames go to gitignored `logs/`: a frame embeds the
// user's game assets and is never committed (AGENTS.md "Legal & IP boundary").

import CoreGraphics
import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct M17AcceptanceRenderTests {
    /// One vanilla line whose lip track decodes, and three times inside it.
    /// Same line `LipSyncRenderRealDataTests` drives, so a failure here and a
    /// pass there is a difference in what is measured, not in what was played.
    private static let voicePath =
        "sound\\voice\\skyrim.esm\\maleeventoned\\wigreeting__000c7917_1.fuz"
    private static let sampleTimes: [Double] = [0.30, 11.0 / 30.0, 0.50]

    /// The head shot's frame, and the fraction of it the mouth region covers.
    private static let size = 800
    private static let mouthRegion = FrameRegion(x: 260, y: 260, width: 280, height: 280)

    /// How many pixels a toggle has to move before it counts as visible. The
    /// same floor the M14 through M16 render gates use for a whole-cell frame;
    /// the mouth has its own, smaller floor, because a mouth is a small part of
    /// a face.
    private static let minimumChangedPixels = 200
    private static let minimumMouthPixels = 20

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

    // MARK: - The mouth

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func lipSyncMovesTheMouthAndOnlyTheMouth() throws {
        let harness = try Self.makeFaceHarness()
        var mouthDeltas: [Int] = []
        var onFrames: [[UInt8]] = []

        for (index, time) in Self.sampleTimes.enumerated() {
            harness.clock.publish(time)
            harness.lip.isEnabled = false
            let off = try Self.frame(harness.renderer, time: Float(time))
            harness.lip.isEnabled = true
            let on = try Self.frame(harness.renderer, time: Float(time))
            onFrames.append(on)

            let total = Self.changedPixels(off, on)
            let mouth = Self.changedPixels(off, on, inRegion: Self.mouthRegion)
            mouthDeltas.append(mouth)
            #expect(
                mouth >= Self.minimumMouthPixels,
                "lip sync at \(time)s moved \(mouth) pixels in the mouth region"
            )
            #expect(
                mouth * 2 >= total,
                "only \(mouth) of \(total) changed pixels were in the mouth region"
            )
            // Same clock, same frame: the A/B pair is a difference the track
            // made, not one the renderer made.
            let repeated = try Self.frame(harness.renderer, time: Float(time))
            #expect(Self.changedPixels(on, repeated) == 0, "\(time)s was not deterministic")

            try Self.writePNG(off, name: "m17-lip-\(index)-off.png")
            try Self.writePNG(on, name: "m17-lip-\(index)-on.png")
        }

        // Two different points in one line are two different mouth shapes. A
        // track that produced one pose and held it would pass every A/B pair
        // above and fail here.
        let acrossTime = Self.changedPixels(
            onFrames[0], onFrames[2], inRegion: Self.mouthRegion
        )
        #expect(
            acrossTime >= Self.minimumMouthPixels,
            "the mouth held one shape across the line: \(acrossTime) pixels"
        )
        print(
            "[INFO] M17 mouth deltas: \(mouthDeltas) px on/off at \(Self.sampleTimes)s,"
                + " \(acrossTime) px between the first and last time,"
                + " line \(Self.voicePath)"
        )
    }

    // MARK: - The view and the menu

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func theConversationTakesTheViewAndPutsTheMenuOverIt() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let assembled = try PlayerBodyFixture.assemble(device: device, root: root)
        let scene = try assembled.builder.buildScene(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: WalkPathRoute.farmCell.x,
            gridY: WalkPathRoute.farmCell.y
        )
        let bounds = try #require(scene.bounds, "no cell bounds — nothing drew")
        let renderer = try FirstPersonRenderRealDataTests.renderer(
            device: device, scene: scene, bounds: bounds
        )
        FirstPersonRenderRealDataTests.frameFirstPerson(renderer, feet: SIMD3(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            bounds.min.z
        ))

        let world = try FirstPersonRenderRealDataTests.frame(renderer)
        let engaged = try Self.engageTheDialogueCamera(renderer)
        let cameraDelta = FirstPersonRenderRealDataTests.changedPixels(world, engaged)
        #expect(
            cameraDelta >= Self.minimumChangedPixels,
            "the dialogue camera moved \(cameraDelta) pixels"
        )

        let withMenu = try Self.bringUpTheMenu(renderer, root: root)
        let menuDelta = FirstPersonRenderRealDataTests.changedPixels(engaged, withMenu)
        #expect(
            menuDelta >= Self.minimumChangedPixels,
            "the dialogue menu drew \(menuDelta) pixels over the conversation"
        )

        try FirstPersonRenderRealDataTests.writePNG(world, name: "m17-conversation-none.png")
        try FirstPersonRenderRealDataTests.writePNG(
            engaged, name: "m17-conversation-camera.png"
        )
        try FirstPersonRenderRealDataTests.writePNG(
            withMenu, name: "m17-conversation-menu.png"
        )
        print(
            "[INFO] M17 conversation deltas: camera \(cameraDelta) px,"
                + " menu \(menuDelta) px over it"
        )
    }

    /// Frames a speaker standing a conversation's distance ahead, which is what
    /// a Talk activation does to the view.
    @MainActor
    private static func engageTheDialogueCamera(_ renderer: Renderer) throws -> [UInt8] {
        let head = renderer.playerEyePosition + renderer.freeFlyCamera.forward * 140
        renderer.setDialogueCameraFocus(DialogueCameraFocus(
            speaker: .plugin(name: "skyrim.esm", objectID: 0x1B079),
            headPosition: head
        ))
        #expect(renderer.isDialogueCameraEngaged)
        return try FirstPersonRenderRealDataTests.frame(renderer)
    }

    /// Brings the vanilla `dialoguemenu.swf` up over the frame the way
    /// `GameViewController.startDialogueMovie` does, publishes a two-row list
    /// into it, and returns the frame it drew.
    @MainActor
    private static func bringUpTheMenu(
        _ renderer: Renderer,
        root: GameDataRoot
    ) throws -> [UInt8] {
        let movie = try SWFMovieLoader(fileSystem: VirtualFileSystem(root: root))
            .load(path: DialogueMenuMovieBridge.moviePath)
        try renderer.setSWFMovie(movie)
        renderer.swfEnabled = true
        renderer.swfScale = 1
        let runtime = try #require(
            try renderer.startSWFRuntime(prepare: DialogueMenuMovieBridge.prepare(runtime:))
        )
        try renderer.updateSWFRuntime { runtime in
            DialogueMenuMovieBridge.activate(runtime: runtime) {}
        }
        let model = DialogueMenuModel(
            speaker: "Speaker",
            speakerKey: .plugin(name: "skyrim.esm", objectID: 0x1B079),
            topics: [
                DialogueTopicEntry(
                    topic: FormID(0x1701), info: FormID(0x1711),
                    text: "I will help you.", endsConversation: false
                ),
                DialogueTopicEntry(
                    topic: FormID(0x1703), info: FormID(0x1713),
                    text: "Farewell.", endsConversation: true
                )
            ]
        )
        try renderer.updateSWFRuntime { runtime in
            DialogueMenuMovieBridge.publish(model, runtime: runtime)
        }
        for _ in 0 ..< 60 {
            try renderer.advanceSWFRuntime()
        }
        #expect(DialogueMenuMovieBridge.diagnostics(runtime: runtime).faults == 0)
        return try FirstPersonRenderRealDataTests.frame(renderer)
    }
}

/// The head-shot harness and the pixel helpers, split off the suite so its own
/// body stays inside the repo's type-length limit.
extension M17AcceptanceRenderTests {
    // MARK: - The face harness

    @MainActor
    private struct FaceHarness {
        let renderer: Renderer
        let lip: LipSyncPlayback
        let clock: VoicePlaybackClock
    }

    /// One vanilla actor's head, its TRI morph targets and one archive lip
    /// track, framed close enough that a mouth is worth measuring. The same
    /// assembly `LipSyncRenderRealDataTests` builds.
    @MainActor
    private static func makeFaceHarness() throws -> FaceHarness {
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
            frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view, scene: scene, camera: faceCamera(assembly: assembly)
        )
        return FaceHarness(renderer: renderer, lip: lip, clock: clock)
    }

    /// Looking at the head from in front and slightly above, close enough that
    /// the mouth region is a mouth.
    private static func faceCamera(assembly: ActorAssembly<ActorRenderAsset>) -> SceneCamera {
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

    // MARK: - Pixels

    @MainActor
    private static func frame(_ renderer: Renderer, time: Float) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(
            width: size, height: size, animationTime: time
        )
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

    private static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) / 4 }
        var changed = 0
        for pixel in stride(from: 0, to: lhs.count, by: 4)
            where Array(lhs[pixel ..< pixel + 4]) != Array(rhs[pixel ..< pixel + 4])
        {
            changed += 1
        }
        return changed
    }

    /// Changed pixels inside one rectangle of the frame, which is what makes a
    /// claim about a mouth rather than about a face.
    private static func changedPixels(
        _ lhs: [UInt8],
        _ rhs: [UInt8],
        inRegion region: FrameRegion
    ) -> Int {
        guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) / 4 }
        var changed = 0
        for row in region.y ..< (region.y + region.height) {
            for column in region.x ..< (region.x + region.width) {
                let pixel = (row * size + column) * 4
                guard pixel + 4 <= lhs.count else { continue }
                if Array(lhs[pixel ..< pixel + 4]) != Array(rhs[pixel ..< pixel + 4]) {
                    changed += 1
                }
            }
        }
        return changed
    }

    private static func writePNG(_ pixels: [UInt8], name: String) throws {
        let url = try PlayerBodyFixture.logsDirectory().appending(path: name)
        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: size,
                height: size,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            return
        }
        try FrameScreenshot.write(image: image, to: url)
    }
}

/// One rectangle of a frame, in pixels from the top left.
private struct FrameRegion {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}
