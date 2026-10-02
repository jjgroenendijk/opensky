// Dialogue camera acceptance, pixel half: engaging the camera over the user's
// cell moves the frame, and releasing it restores the view exactly. Both
// frames render at one animation time, so only the camera differs. Needs a
// Metal 4 device and the install; frames go to gitignored `logs/`.

import Foundation
import Metal
import MetalKit
@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
@testable import OpenSkyWorld
@testable import OpenSkyWorldInterface
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct DialogueCameraRenderRealDataTests {
    /// How many pixels the override has to move before it counts as visible.
    /// The same floor the M14, M15 and M16 render gates use.
    private static let minimumChangedPixels = 200

    /// A first-person field of view no mode's default happens to be, so
    /// "the projection was restored" is a claim with a witness rather than two
    /// equal numbers agreeing by accident.
    private static let probeFOVYDegrees: Float = 95

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func engagingTheDialogueCameraMovesTheFrameAndReleasingRestoresIt() throws {
        let cell = try PlayerBodyFixture.stage(
            gridX: WalkPathRoute.farmCell.x, gridY: WalkPathRoute.farmCell.y
        )
        let renderer = try cell.renderer()

        // Stand in the middle of the cell looking east, in first person, at a
        // field of view that is nobody's default.
        let feet = SIMD3<Float>(
            (cell.bounds.min.x + cell.bounds.max.x) / 2,
            (cell.bounds.min.y + cell.bounds.max.y) / 2,
            cell.bounds.min.z
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
        return RenderedPixels.read(texture)
    }
}
