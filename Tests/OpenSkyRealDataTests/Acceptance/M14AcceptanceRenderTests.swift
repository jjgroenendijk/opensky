// Locomotion acceptance, pixel half: the player is drawn, the drawing follows
// the locomotion state, and the two camera modes draw different frames. A
// changed state is also checked against a frame built at that state from the
// start, which must match byte for byte. Frames stay in gitignored `logs/`.

import Foundation
import Metal
import MetalKit
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

/// The device and the install one render run is bound to, passed as one value
/// so the assertion helpers stay inside the parameter cap.
private struct M14RenderInstall {
    let device: MTLDevice
    let root: GameDataRoot
}

/// The renderer and the spot on the terrain every frame of one run is taken
/// from, passed as one value for the same reason.
@MainActor
private struct M14RenderStage {
    let renderer: Renderer
    let feet: SIMD3<Float>
}

struct M14AcceptanceRenderTests {
    /// How many pixels a state change has to move before it counts as visible.
    /// Well above the handful a rounding difference could touch and far below a
    /// whole body's worth, so the number is a floor rather than a tuned value.
    private static let minimumChangedPixels = 200

    private static let step: Float = 1.0 / 120

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func drawsThePlayerFollowingItsLocomotionState() throws {
        let cell = try PlayerBodyFixture.stage()
        let assembled = cell.assembled
        let feet = try cell.terrainStart()
        let renderer = try cell.renderer()
        var report: [String] = []

        let empty = try Self.thirdPersonFrame(renderer, feet: feet)
        try renderer.setPlayerBody(assembled.body)
        try renderer.setPlayerFirstPersonRig(assembled.arms)

        let idle = try Self.settle(assembled, renderer: renderer, feet: feet)
        let bodyPixels = FirstPersonRenderRealDataTests.changedPixels(empty, idle)
        report.append("third person idle vs no body: \(bodyPixels) changed pixels")
        #expect(bodyPixels > Self.minimumChangedPixels, "the body drew nothing in third person")

        try Self.assertStateChangeIsVisibleAndReproducible(
            assembled,
            install: M14RenderInstall(device: cell.device, root: cell.root),
            stage: M14RenderStage(renderer: renderer, feet: feet),
            idle: idle,
            report: &report
        )
        try Self.assertCameraModeSwitchIsReproducible(
            assembled, renderer: renderer, feet: feet, report: &report
        )

        try PlayerBodyFixture.write(
            report.joined(separator: "\n") + "\n", to: "m14-acceptance-render.log"
        )
        try FirstPersonRenderRealDataTests.writePNG(idle, name: "m14-third-person-idle.png")
    }

    // MARK: - Assertions

    /// Idle, sprint, and a second player driven by the same input. The sprint
    /// must differ from idle, and both sprints must match byte for byte. A
    /// return to idle would not do: a playing idle clip changes the frame.
    @MainActor
    private static func assertStateChangeIsVisibleAndReproducible(
        _ assembled: PlayerBodyFixture.Assembled,
        install: M14RenderInstall,
        stage: M14RenderStage,
        idle: [UInt8],
        report: inout [String]
    ) throws {
        let renderer = stage.renderer
        let feet = stage.feet
        let sprinting = try Self.drive(
            assembled,
            renderer: renderer,
            feet: feet,
            input: CameraInput(moveForward: 1, sprint: true, dt: step)
        )
        let changed = FirstPersonRenderRealDataTests.changedPixels(idle, sprinting)
        report.append("third person sprint vs idle: \(changed) changed pixels")
        #expect(
            changed >= Self.minimumChangedPixels,
            "sprinting changed only \(changed) pixels against idle"
        )

        // The same sequence from a graph that has never been stepped.
        let second = try PlayerBodyFixture.assemble(
            device: install.device, root: install.root
        )
        try renderer.setPlayerBody(second.body)
        try renderer.setPlayerFirstPersonRig(second.arms)
        _ = try Self.settle(second, renderer: renderer, feet: feet)
        let again = try Self.drive(
            second,
            renderer: renderer,
            feet: feet,
            input: CameraInput(moveForward: 1, sprint: true, dt: step)
        )
        let residual = FirstPersonRenderRealDataTests.changedPixels(sprinting, again)
        report.append("second player at the same state: \(residual) changed pixels")
        #expect(
            residual == 0,
            "the same input from a fresh graph drew a different frame (\(residual) pixels)"
        )
        try renderer.setPlayerBody(assembled.body)
        try renderer.setPlayerFirstPersonRig(assembled.arms)
    }

    /// The camera-mode axis: third person draws the body, first person draws
    /// the arms, and switching back reproduces the third-person frame exactly.
    @MainActor
    private static func assertCameraModeSwitchIsReproducible(
        _ assembled: PlayerBodyFixture.Assembled,
        renderer: Renderer,
        feet: SIMD3<Float>,
        report: inout [String]
    ) throws {
        let third = try Self.settle(assembled, renderer: renderer, feet: feet)

        FirstPersonRenderRealDataTests.frameFirstPerson(renderer, feet: feet)
        FirstPersonRenderRealDataTests.place(assembled, renderer: renderer, feet: feet)
        let first = try FirstPersonRenderRealDataTests.frame(renderer)
        let modeChange = FirstPersonRenderRealDataTests.changedPixels(third, first)
        report.append("first person vs third person: \(modeChange) changed pixels")
        #expect(
            modeChange >= Self.minimumChangedPixels,
            "switching camera mode changed only \(modeChange) pixels"
        )

        let back = try Self.thirdPersonFrame(renderer, feet: feet, place: assembled)
        let residual = FirstPersonRenderRealDataTests.changedPixels(third, back)
        report.append("third person after a mode round trip: \(residual) changed pixels")
        #expect(residual == 0, "the mode round trip drew a different frame")
        try FirstPersonRenderRealDataTests.writePNG(first, name: "m14-first-person-idle.png")
    }

    // MARK: - Driving

    /// Puts the eye where third person puts it and renders one frame.
    @MainActor
    private static func thirdPersonFrame(
        _ renderer: Renderer,
        feet: SIMD3<Float>,
        place assembled: PlayerBodyFixture.Assembled? = nil
    ) throws -> [UInt8] {
        renderer.freeFlyCamera = FreeFlyCamera(
            position: feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
        renderer.setMovementMode(.thirdPerson)
        // `setMovementMode` seats the capsule under the eye; the orbit pull-back
        // happens in `advancePlayer`, which only a live frame loop runs. Doing
        // it here is what puts the camera behind the player rather than inside
        // them.
        renderer.freeFlyCamera.position = renderer.thirdPersonCamera.resolve(
            feetPosition: feet,
            yaw: renderer.freeFlyCamera.yaw,
            pitch: renderer.freeFlyCamera.pitch,
            collisionQuery: { _ in [] }
        )
        if let assembled {
            FirstPersonRenderRealDataTests.place(assembled, renderer: renderer, feet: feet)
        }
        return try FirstPersonRenderRealDataTests.frame(renderer)
    }

    /// Drives one held input for a second of fixed steps and renders the frame
    /// it produced.
    @MainActor
    private static func drive(
        _ assembled: PlayerBodyFixture.Assembled,
        renderer: Renderer,
        feet: SIMD3<Float>,
        input: CameraInput
    ) throws -> [UInt8] {
        for _ in 0 ..< LocomotionDriveHarness.secondOfSteps {
            FirstPersonRenderRealDataTests.drive(assembled, feet: feet, input: input)
        }
        return try thirdPersonFrame(renderer, feet: feet, place: assembled)
    }

    /// The standing player: no input held, driven long enough for the graph to
    /// settle back into its idle state.
    @MainActor
    private static func settle(
        _ assembled: PlayerBodyFixture.Assembled,
        renderer: Renderer,
        feet: SIMD3<Float>
    ) throws -> [UInt8] {
        try drive(assembled, renderer: renderer, feet: feet, input: CameraInput(dt: step))
    }
}
