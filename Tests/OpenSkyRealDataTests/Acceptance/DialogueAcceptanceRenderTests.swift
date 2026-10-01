// M17 acceptance, pixel half, as changed-pixel counts. The mouth region must
// change and hold most of the frame's change. The camera and menu toggles run
// together on one real cell, in the order a conversation applies them. Needs
// a Metal 4 device and the install; frames go to gitignored `logs/`.

import CoreGraphics
import Foundation
import Metal
import MetalKit
@testable import OpenSkyAudio
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyFormatsAudio
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldTesting
import simd
import TagsTesting
import Testing

@Suite(.tags(.acceptance, .gpu))
struct DialogueAcceptanceRenderTests {
    /// Three times inside the `HeimskrFace` lip track.
    private static let sampleTimes: [Double] = [0.30, 11.0 / 30.0, 0.50]

    /// The head shot's frame, and the fraction of it the mouth region covers.
    private static let size = HeimskrFace.size
    private static let mouthRegion = FrameRegion(x: 260, y: 260, width: 280, height: 280)

    /// How many pixels a toggle has to move before it counts as visible. The
    /// same floor the M14 through M16 render gates use for a whole-cell frame;
    /// the mouth has its own, smaller floor, because a mouth is a small part of
    /// a face.
    private static let minimumChangedPixels = 200
    private static let minimumMouthPixels = 20

    // MARK: - The mouth

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func lipSyncMovesTheMouthAndOnlyTheMouth() throws {
        let harness = try HeimskrFace.lipSyncHarness()
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

            try FirstPersonRenderRealDataTests.writePNG(
                off, name: "m17-lip-\(index)-off.png", size: Self.size
            )
            try FirstPersonRenderRealDataTests.writePNG(
                on, name: "m17-lip-\(index)-on.png", size: Self.size
            )
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
                + " line \(HeimskrFace.voicePath)"
        )
    }

    // MARK: - The view and the menu

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func theConversationTakesTheViewAndPutsTheMenuOverIt() throws {
        let cell = try PlayerBodyFixture.stage(
            gridX: WalkPathRoute.farmCell.x, gridY: WalkPathRoute.farmCell.y
        )
        let renderer = try cell.renderer()
        FirstPersonRenderRealDataTests.frameFirstPerson(renderer, feet: SIMD3(
            (cell.bounds.min.x + cell.bounds.max.x) / 2,
            (cell.bounds.min.y + cell.bounds.max.y) / 2,
            cell.bounds.min.z
        ))

        let world = try FirstPersonRenderRealDataTests.frame(renderer)
        let engaged = try Self.engageTheDialogueCamera(renderer)
        let cameraDelta = FirstPersonRenderRealDataTests.changedPixels(world, engaged)
        #expect(
            cameraDelta >= Self.minimumChangedPixels,
            "the dialogue camera moved \(cameraDelta) pixels"
        )

        let withMenu = try Self.bringUpTheMenu(renderer, root: cell.root)
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
            headPosition: head
        ))
        #expect(renderer.isDialogueCameraEngaged)
        return try FirstPersonRenderRealDataTests.frame(renderer)
    }

    /// Brings the vanilla `dialoguemenu.swf` up over the frame the way
    /// `DialogueMenuController.startMovie()` does, publishes a two-row list
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
                    info: FormID(0x1711),
                    text: "I will help you.", endsConversation: false
                ),
                DialogueTopicEntry(
                    info: FormID(0x1713),
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
extension DialogueAcceptanceRenderTests {
    // MARK: - Pixels

    @MainActor
    private static func frame(_ renderer: Renderer, time: Float) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(
            width: size, height: size, animationTime: time
        )
        return RenderedPixels.read(texture)
    }

    private static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        RenderedPixels.changedCount(lhs, rhs)
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
}

/// One rectangle of a frame, in pixels from the top left.
private struct FrameRegion {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}
