// M14 acceptance, pixel half (issue #191): the player is drawn, the drawing
// follows the locomotion state, and the two camera modes draw two different
// things — measured as changed-pixel counts rather than eyeballed.
//
// Three frames rather than two, for the reason `M12AcceptanceRenderTests`
// recorded and `M13AcceptanceRenderTests` reused: the strongest statement
// available is not "the count changed" but "the frame reached by advancing is
// byte-identical to a frame built at that state all along". Both axes the gate
// names get that treatment — a locomotion state change, and a camera-mode
// switch.
//
// Gated on a Metal 4 device *and* on the install, because what is being drawn
// is the user's own player mesh under the user's own animation data. The
// accounting half of the gate, `M14AcceptanceTests`, needs neither, and the
// real-data half, `M14AcceptanceRealDataTests`, needs no device — so the route
// and its coverage numbers still stand on a device-less runner.
//
// Rendered frames go to gitignored `logs/`: a frame embeds the user's game art
// and is never committed (AGENTS.md "Legal & IP boundary").

import Foundation
import Metal
import MetalKit
@testable import opensky
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
    func drawsThePlayerFollowingItsLocomotionState() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let assembled = try PlayerBodyFixture.assemble(device: device, root: root)
        let scene = try assembled.builder.buildScene(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: FirstRenderCell.gridX,
            gridY: FirstRenderCell.gridY
        )
        let bounds = try #require(scene.bounds, "no world bounds — nothing drew")
        let terrain = try #require(LocomotionRealTerrain.terrainField(root: root))
        let feet = LocomotionRealTerrain.startPosition(on: terrain)
        let renderer = try FirstPersonRenderRealDataTests.renderer(
            device: device, scene: scene, bounds: bounds
        )
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
            install: M14RenderInstall(device: device, root: root),
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

    /// The locomotion-state axis, all three frames: idle, sprinting, and a
    /// second player driven through the identical input sequence from a fresh
    /// graph. The sprint has to differ from idle by more than noise, and the
    /// independently-driven sprint frame has to be the first one byte for byte
    /// — which is what says the difference is the state rather than the
    /// republish, and that the state is reached deterministically.
    ///
    /// The cross-check is a second player rather than a return to idle,
    /// because a locomotion clip is still playing while the player stands
    /// still: two idle frames a second apart are two phases of the same
    /// animation and are legitimately different pictures. Two runs of the same
    /// input from the same start are not.
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
