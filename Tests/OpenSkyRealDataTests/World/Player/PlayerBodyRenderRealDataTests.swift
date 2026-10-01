// Offscreen render of the third-person player body on the real install. The
// body draws in third person and not in first person (only its shadow stays).
// A posed body keeps about the bind-pose silhouette, which a torn mesh cannot.
// A locomotion state change changes the frame. A body reassembled at a pose
// matches one assembled there from the start; the check uses assembly, because
// a crossfading graph is time-dependent. Captures stay in gitignored `logs/`.

import Foundation
import Metal
import MetalKit
@testable import OpenSkyFormatsCore
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct PlayerBodyRenderRealDataTests {
    /// What one assertion needs to re-pose the body and render it again: the
    /// live renderer, the loaded install, and where the body is standing.
    /// Bundled so the assertion signatures stay inside the parameter cap.
    @MainActor
    private struct Stage {
        let renderer: Renderer
        let assembled: PlayerBodyFixture.Assembled
        let root: GameDataRoot
        let device: MTLDevice
        let feet: SIMD3<Float>
    }

    private static let size = 640

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func drawsTheBodyInThirdPersonOnly() throws {
        let cell = try PlayerBodyFixture.stage()
        let assembled = cell.assembled
        let feet = try cell.terrainStart()
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size), device: cell.device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: cell.scene.renderScene,
            camera: SceneCamera.framing(bounds: cell.bounds)
        )
        var report: [String] = []

        // Put the camera exactly where the app puts it: the capsule standing on
        // the launch cell's real ground, the eye orbited back to the resolved
        // third-person position. Nothing here is a test-only framing.
        Self.frameThirdPerson(renderer, feet: feet)
        let empty = try Self.frame(renderer)

        // Pose the body from a second of standing still. A second rather than
        // one step: the graph's opening update has every crossfade at zero and
        // every clip at time zero, which is a pose the player is never actually
        // seen in.
        for _ in 0 ..< LocomotionDriveHarness.secondOfSteps {
            Self.step(assembled.bridge, feet: feet, input: CameraInput(dt: 1.0 / 120))
        }
        assembled.body.place(feetPosition: feet, yaw: renderer.freeFlyCamera.yaw)
        assembled.body.animation.update(at: 0)
        try renderer.setPlayerBody(assembled.body)

        let thirdPerson = try Self.frame(renderer)
        let bodyPixels = Self.changedPixels(empty, thirdPerson)
        report.append("third person vs no body: \(bodyPixels) changed pixels")
        #expect(bodyPixels > 0, "the player body drew nothing in third person")

        try Self.assertPosedBodyIsStillAFigure(
            renderer, empty: empty, posed: thirdPerson, report: &report
        )

        // First person must not draw the body; the camera stays put. The frames
        // still differ a little: the unseen body casts a shadow
        // (`PlayerRigVisibility.castsBodyShadow`). The body itself must be gone.
        renderer.movementMode = .walk
        let firstPerson = try Self.frame(renderer)
        let shadowPixels = Self.changedPixels(empty, firstPerson)
        report.append("first person vs no body: \(shadowPixels) changed pixels")
        // The shadow alone measures about 0.27 of the body on this cell, and a
        // drawn body would put the ratio at or above 1. Half is the midpoint
        // that separates them without pinning either number.
        #expect(
            shadowPixels * 2 < bodyPixels,
            "first person changed \(shadowPixels) pixels against the body's \(bodyPixels)"
        )

        renderer.movementMode = .thirdPerson
        let stage = Stage(
            renderer: renderer, assembled: assembled, root: cell.root, device: cell.device,
            feet: feet
        )
        try Self.assertStateChangeChangesTheFrame(
            stage, reference: thirdPerson, report: &report
        )
        try Self.assertReassemblyIsByteIdentical(
            stage, reference: thirdPerson, report: &report
        )
        try PlayerBodyFixture.write(
            report.joined(separator: "\n") + "\n", to: "player-body-render.log"
        )
        try Self.writePNG(thirdPerson, name: "player-body-third-person.png")
    }

    // MARK: - Assertions

    /// The posed body and the bind-pose body cover about the same ground. A
    /// mismatched skinning convention throws shards across the frame and
    /// covers several times more, so bounding the ratio catches it without
    /// pinning a pose. Both captures go to gitignored `logs/`.
    @MainActor
    private static func assertPosedBodyIsStillAFigure(
        _ renderer: Renderer,
        empty: [UInt8],
        posed: [UInt8],
        report: inout [String]
    ) throws {
        renderer.actorAnimationsEnabled = false
        let bindPose = try frame(renderer)
        renderer.actorAnimationsEnabled = true
        try writePNG(bindPose, name: "player-body-bind-pose.png")

        let bindPixels = changedPixels(empty, bindPose)
        let posedPixels = changedPixels(empty, posed)
        let moved = changedPixels(bindPose, posed)
        report.append("bind pose vs no body: \(bindPixels) changed pixels")
        report.append("posed vs bind pose: \(moved) changed pixels")
        #expect(bindPixels > 0, "the bind-pose body drew nothing")

        let coverage = Float(posedPixels) / Float(max(bindPixels, 1))
        report.append("posed/bind coverage ratio: \(coverage)")
        #expect(
            coverage > 0.6 && coverage < 1.6,
            "posed body covers \(posedPixels) pixels against the bind pose's \(bindPixels)"
        )
    }

    /// Walking is not idling. Driving the graph with a held forward key for a
    /// second and re-posing the body has to move pixels.
    @MainActor
    private static func assertStateChangeChangesTheFrame(
        _ stage: Stage,
        reference: [UInt8],
        report: inout [String]
    ) throws {
        let walking = CameraInput(moveForward: 1, boost: true, dt: 1.0 / 120)
        for _ in 0 ..< LocomotionDriveHarness.secondOfSteps {
            step(stage.assembled.bridge, feet: stage.feet, input: walking)
        }
        stage.assembled.body.place(
            feetPosition: stage.feet, yaw: stage.renderer.freeFlyCamera.yaw
        )
        stage.assembled.body.animation.update(at: 0)
        let running = try frame(stage.renderer)
        let changed = changedPixels(reference, running)
        report.append("idle vs running: \(changed) changed pixels")
        #expect(changed > 0, "a locomotion state change moved no pixels")
    }

    /// Reassembling the body — what an equipment change does — and re-posing it
    /// to the same pose has to produce the same frame, byte for byte.
    @MainActor
    private static func assertReassemblyIsByteIdentical(
        _ stage: Stage,
        reference: [UInt8],
        report: inout [String]
    ) throws {
        let palettes = PlayerBodyFixture.palettes(of: stage.assembled.body)
        let rebuilt = try PlayerBodyFixture.assemble(
            device: stage.device, root: stage.root
        )
        for _ in 0 ..< LocomotionDriveHarness.secondOfSteps {
            step(rebuilt.bridge, feet: stage.feet, input: CameraInput(dt: 1.0 / 120))
        }
        rebuilt.body.place(
            feetPosition: stage.feet, yaw: stage.renderer.freeFlyCamera.yaw
        )
        rebuilt.body.animation.update(at: 0)
        try stage.renderer.setPlayerBody(rebuilt.body)
        let rebuiltFrame = try frame(stage.renderer)
        report.append(
            "reassembled vs original: "
                + "\(changedPixels(reference, rebuiltFrame)) changed pixels"
        )
        // The graph is deterministic, so one step from a fresh instance
        // reproduces the pose the reference frame was built from.
        #expect(PlayerBodyFixture.palettes(of: rebuilt.body).count == palettes.count)
        #expect(rebuiltFrame == reference, "reassembly changed the frame")
    }

    // MARK: - Driving

    /// One fixed step of the bridge at a fixed capsule pose. The controller is
    /// deliberately out of the loop here: this test is about what draws, and a
    /// moving capsule would change the framing as well as the pose.
    private static func step(
        _ bridge: LocomotionBridge,
        feet: SIMD3<Float>,
        input: CameraInput
    ) {
        bridge.acceptFrame(input)
        _ = bridge.plan(LocomotionStepState(
            feetPosition: feet,
            verticalVelocity: 0,
            isGrounded: true,
            yaw: 0,
            dt: WalkController.fixedTimeStep
        ))
    }

    /// Stands the capsule at `feet` and puts the eye at the resolved
    /// third-person orbit position, looking slightly down at the body — the
    /// same path `Renderer.advanceCamera` takes, so what the capture shows is
    /// what the app shows.
    @MainActor
    private static func frameThirdPerson(_ renderer: Renderer, feet: SIMD3<Float>) {
        renderer.freeFlyCamera = FreeFlyCamera(
            position: feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: MatrixMath.radians(fromDegrees: -10)
        )
        renderer.setMovementMode(.thirdPerson)
        renderer.freeFlyCamera.position = renderer.thirdPersonCamera.resolve(
            feetPosition: feet,
            yaw: renderer.freeFlyCamera.yaw,
            pitch: renderer.freeFlyCamera.pitch,
            collisionQuery: { _ in [] }
        )
    }

    // MARK: - Pixels

    @MainActor
    private static func frame(_ renderer: Renderer) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(width: size, height: size)
        return RenderedPixels.read(texture)
    }

    private static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        RenderedPixels.changedCount(lhs, rhs)
    }

    /// Writes one capture into gitignored `logs/` for human review. A rendered
    /// frame embeds the user's own game assets and is never committed.
    private static func writePNG(_ pixels: [UInt8], name: String) throws {
        try RenderedPixels.writePNG(
            pixels, width: size, height: size,
            to: PlayerBodyFixture.logsDirectory().appending(path: name)
        )
    }
}
