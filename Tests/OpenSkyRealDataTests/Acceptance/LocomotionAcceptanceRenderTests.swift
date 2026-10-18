// Locomotion acceptance, pixel half: the player is drawn, the drawing follows
// the locomotion state, and the two camera modes draw different frames. A
// changed state is also checked against a frame built at that state from the
// start, which must match byte for byte. Frames stay in gitignored `.logs/`.

import Foundation
import Metal
import MetalKit
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
import OpenSkyPlayer
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import simd
import Testing

/// The device and the install one render run is bound to, passed as one value
/// so the assertion helpers stay inside the parameter cap.
private struct LocomotionRenderInstall {
    let device: MTLDevice
    let root: GameDataRoot
}

/// The session and the spot on the terrain every frame of one run is taken
/// from, passed as one value for the same reason.
@MainActor
private struct LocomotionRenderStage {
    let gameSession: GameSession
    let feet: SIMD3<Float>
}

@Suite(.tags(.acceptance, .gpu))
struct LocomotionAcceptanceRenderTests {
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
        let gameSession = try cell.makeSession()
        var report: [String] = []

        let empty = try Self.thirdPersonFrame(gameSession, feet: feet)
        try gameSession.setPlayerBody(assembled.body)
        try gameSession.setPlayerFirstPersonRig(assembled.arms)

        let idle = try Self.settle(assembled, gameSession: gameSession, feet: feet)
        let bodyPixels = FirstPersonRenderRealDataTests.changedPixels(empty, idle)
        report.append("third person idle vs no body: \(bodyPixels) changed pixels")
        #expect(bodyPixels > Self.minimumChangedPixels, "the body drew nothing in third person")

        try Self.assertStateChangeIsVisibleAndReproducible(
            assembled,
            install: LocomotionRenderInstall(device: cell.device, root: cell.root),
            stage: LocomotionRenderStage(gameSession: gameSession, feet: feet),
            idle: idle,
            report: &report
        )
        try Self.assertCameraModeSwitchIsReproducible(
            assembled, gameSession: gameSession, feet: feet, report: &report
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
        install: LocomotionRenderInstall,
        stage: LocomotionRenderStage,
        idle: [UInt8],
        report: inout [String]
    ) throws {
        let gameSession = stage.gameSession
        let feet = stage.feet
        let sprinting = try Self.drive(
            assembled,
            gameSession: gameSession,
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
        try gameSession.setPlayerBody(second.body)
        try gameSession.setPlayerFirstPersonRig(second.arms)
        _ = try Self.settle(second, gameSession: gameSession, feet: feet)
        let again = try Self.drive(
            second,
            gameSession: gameSession,
            feet: feet,
            input: CameraInput(moveForward: 1, sprint: true, dt: step)
        )
        let residual = FirstPersonRenderRealDataTests.changedPixels(sprinting, again)
        report.append("second player at the same state: \(residual) changed pixels")
        #expect(
            residual == 0,
            "the same input from a fresh graph drew a different frame (\(residual) pixels)"
        )
        try gameSession.setPlayerBody(assembled.body)
        try gameSession.setPlayerFirstPersonRig(assembled.arms)
    }

    /// The camera-mode axis: third person draws the body, first person draws
    /// the arms, and switching back reproduces the third-person frame exactly.
    @MainActor
    private static func assertCameraModeSwitchIsReproducible(
        _ assembled: PlayerBodyFixture.Assembled,
        gameSession: GameSession,
        feet: SIMD3<Float>,
        report: inout [String]
    ) throws {
        let renderer = gameSession.renderer
        let third = try Self.settle(assembled, gameSession: gameSession, feet: feet)

        FirstPersonRenderRealDataTests.frameFirstPerson(gameSession, feet: feet)
        FirstPersonRenderRealDataTests.place(assembled, gameSession: gameSession, feet: feet)
        let first = try FirstPersonRenderRealDataTests.frame(renderer)
        let modeChange = FirstPersonRenderRealDataTests.changedPixels(third, first)
        report.append("first person vs third person: \(modeChange) changed pixels")
        #expect(
            modeChange >= Self.minimumChangedPixels,
            "switching camera mode changed only \(modeChange) pixels"
        )

        let back = try Self.thirdPersonFrame(gameSession, feet: feet, place: assembled)
        let residual = FirstPersonRenderRealDataTests.changedPixels(third, back)
        report.append("third person after a mode round trip: \(residual) changed pixels")
        #expect(residual == 0, "the mode round trip drew a different frame")
        try FirstPersonRenderRealDataTests.writePNG(first, name: "m14-first-person-idle.png")
    }

    // MARK: - Driving

    /// Puts the eye where third person puts it and renders one frame.
    @MainActor
    private static func thirdPersonFrame(
        _ gameSession: GameSession,
        feet: SIMD3<Float>,
        place assembled: PlayerBodyFixture.Assembled? = nil
    ) throws -> [UInt8] {
        let renderer = gameSession.renderer
        gameSession.freeFlyCamera = FreeFlyCamera(
            position: feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
        gameSession.setMovementMode(.thirdPerson)
        // `setMovementMode` seats the capsule under the eye; the orbit pull-back
        // happens in `advancePlayer`, which only a live frame loop runs. Doing
        // it here is what puts the camera behind the player rather than inside
        // them.
        gameSession.freeFlyCamera.position = gameSession.thirdPersonCamera.resolve(
            feetPosition: feet,
            yaw: gameSession.freeFlyCamera.yaw,
            pitch: gameSession.freeFlyCamera.pitch,
            collisionQuery: { _ in [] }
        )
        if let assembled {
            FirstPersonRenderRealDataTests.place(assembled, gameSession: gameSession, feet: feet)
        }
        return try FirstPersonRenderRealDataTests.frame(renderer)
    }

    /// Drives one held input for a second of fixed steps and renders the frame
    /// it produced.
    @MainActor
    private static func drive(
        _ assembled: PlayerBodyFixture.Assembled,
        gameSession: GameSession,
        feet: SIMD3<Float>,
        input: CameraInput
    ) throws -> [UInt8] {
        for _ in 0 ..< LocomotionDriveHarness.secondOfSteps {
            FirstPersonRenderRealDataTests.drive(assembled, feet: feet, input: input)
        }
        return try thirdPersonFrame(gameSession, feet: feet, place: assembled)
    }

    /// The standing player: no input held, driven long enough for the graph to
    /// settle back into its idle state.
    @MainActor
    private static func settle(
        _ assembled: PlayerBodyFixture.Assembled,
        gameSession: GameSession,
        feet: SIMD3<Float>
    ) throws -> [UInt8] {
        try drive(assembled, gameSession: gameSession, feet: feet, input: CameraInput(dt: step))
    }
}
