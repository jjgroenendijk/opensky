// M17.4 acceptance, pixel half (issue #427): engaging the dialogue camera over
// the user's own cell moves the frame, and releasing it puts the previous view
// back exactly.
//
// `DialogueCameraTests` already proves the framing math from synthetic
// transforms. What it cannot prove is that the override reaches the passes: the
// eye is written into `Renderer.freeFlyCamera`, which the scene pass, the
// shadow fit and the culling all read separately, and an override that failed to
// land there would leave every one of those unit tests green while the frame
// never moved.
//
// Both frames are rendered at the same animation time through
// `renderOffscreen(width:height:animationTime:)`, so the only difference
// between them is the camera. A test that let the clock run would measure a
// swaying tree.
//
// Gated on a Metal 4 device *and* on the install, because what is being drawn is
// the user's own cell geometry. Rendered frames go to gitignored `logs/`: a
// frame embeds the user's game art and is never committed (AGENTS.md "Legal &
// IP boundary").

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct DialogueCameraRenderRealDataTests {
    /// How many pixels the override has to move before it counts as visible.
    /// The same floor the M14, M15 and M16 render gates use.
    private static let minimumChangedPixels = 200

    /// A first-person field of view no mode's default happens to be, so
    /// "the projection was restored" is a claim with a witness rather than two
    /// equal numbers agreeing by accident.
    private static let probeFOVYDegrees: Float = 95

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
    func engagingTheDialogueCameraMovesTheFrameAndReleasingRestoresIt() throws {
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

        // Stand in the middle of the cell looking east, in first person, at a
        // field of view that is nobody's default.
        let feet = SIMD3<Float>(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            bounds.min.z
        )
        FirstPersonRenderRealDataTests.frameFirstPerson(renderer, feet: feet)
        renderer.setFirstPersonFOVY(
            radians: MatrixMath.radians(fromDegrees: Self.probeFOVYDegrees)
        )
        let playerPose = renderer.freeFlyCamera
        let playerFOV = renderer.activeFOVYRadians
        let released = try Self.frame(renderer)
        #expect(!renderer.isDialogueCameraEngaged)

        // Somebody standing a conversation's distance ahead of the player.
        let speaker = renderer.playerEyePosition + renderer.freeFlyCamera.forward * 140
        renderer.setDialogueCameraFocus(DialogueCameraFocus(
            speaker: .plugin(name: "skyrim.esm", objectID: 0x1B079),
            headPosition: speaker
        ))
        #expect(renderer.isDialogueCameraEngaged)
        let pose = try #require(renderer.dialogueCameraPose)
        #expect(pose.target == speaker)
        // The eye left the player's head and is looking back at the speaker.
        #expect(simd_distance(pose.eye, playerPose.position) > 1)
        #expect(simd_dot(simd_normalize(pose.target - pose.eye), playerPose.forward) > 0.5)
        // A conversation projects at the shared world angle, not at the
        // first-person setting the player chose.
        #expect(renderer.activeFOVYRadians == DialogueCamera.fovYRadians)
        #expect(renderer.activeFOVYRadians != playerFOV)

        let engaged = try Self.frame(renderer)
        let delta = FirstPersonRenderRealDataTests.changedPixels(released, engaged)
        #expect(
            delta >= Self.minimumChangedPixels,
            "the dialogue camera moved \(delta) pixels"
        )

        renderer.setDialogueCameraFocus(nil)
        #expect(!renderer.isDialogueCameraEngaged)
        #expect(renderer.dialogueCameraPose == nil)
        #expect(renderer.freeFlyCamera.position == playerPose.position)
        #expect(renderer.freeFlyCamera.yaw == playerPose.yaw)
        #expect(renderer.freeFlyCamera.pitch == playerPose.pitch)
        #expect(renderer.activeFOVYRadians == playerFOV)
        // The view the player had back, pixel for pixel.
        let restored = try Self.frame(renderer)
        let restoredDelta = FirstPersonRenderRealDataTests.changedPixels(released, restored)
        #expect(restoredDelta == 0, "releasing left \(restoredDelta) pixels changed")

        try FirstPersonRenderRealDataTests.writePNG(
            released, name: "dialogue-camera-released.png"
        )
        try FirstPersonRenderRealDataTests.writePNG(
            engaged, name: "dialogue-camera-engaged.png"
        )
    }

    /// One frame at a fixed animation time, so two frames differ only by the
    /// camera that took them.
    @MainActor
    private static func frame(_ renderer: Renderer) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(
            width: FirstPersonRenderRealDataTests.size,
            height: FirstPersonRenderRealDataTests.size,
            animationTime: 0
        )
        var result = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        result.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return result
    }
}
