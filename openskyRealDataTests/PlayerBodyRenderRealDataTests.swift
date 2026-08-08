// Env-gated offscreen render of the third-person player body (issue #189) over
// the user's own Skyrim SE install (read-only external input; a rendered frame
// embeds the user's assets, so captures go to gitignored `logs/` and are never
// committed — AGENTS.md "Legal & IP").
//
// Three things are proved with pixels rather than with numbers:
//
// * The body actually draws in third person and actually does not draw in first
//   person, against the same scene and the same camera pose — leaving only the
//   shadow it goes on casting there (issue #356).
// * A posed body is still a standing figure: its silhouette stays within a
//   bound of the bind-pose body's, which a mesh torn apart by a mismatched
//   skinning convention cannot pass (issue #354).
// * A locomotion state change changes the frame — a bound-but-inert graph would
//   leave it byte-identical.
// * The M12/M13 cross-check: a body reassembled at a pose is byte-identical to
//   one assembled at that pose from the start. It is applied on the *assembly*
//   axis rather than on the graph's, because a crossfading state machine is
//   time-dependent by construction and two runs that reach a state by different
//   routes are not required to agree on the frame mid-blend.
//
// Run with
// `make realtest T='PlayerBodyRenderRealDataTests/drawsTheBodyInThirdPersonOnly()'`.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

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
    func drawsTheBodyInThirdPersonOnly() throws {
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
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: scene.renderScene,
            camera: SceneCamera.framing(bounds: bounds)
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

        // First person must not draw it: the eye is inside the head until 14.7.
        // The camera pose is left exactly where it is, so the two frames differ
        // only in whether the body drew. They are not byte-identical, though:
        // since #356 a body the camera cannot see still rasterizes into the
        // shadow map (`PlayerRigVisibility.castsBodyShadow` holds for every
        // player-controlled mode), so the body's own shadow still darkens the
        // ground it stands on. What must not survive into the frame is the
        // body, which covers far more of it than its shadow does.
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
            renderer: renderer, assembled: assembled, root: root, device: device, feet: feet
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

    /// The bound a torn mesh cannot pass (issue #354).
    ///
    /// A body posed by the idle graph and the same body drawn from its NIF
    /// bind palette are the same figure standing in the same place: the pose
    /// moves limbs, so the two frames are not identical, but the silhouette
    /// covers roughly the same ground. A mesh skinned through a mismatched
    /// convention does not fail quietly — it throws long flat shards across
    /// the frame, and its coverage runs to several times the bind-pose body's.
    /// Bounding the ratio therefore catches the whole family of composition
    /// faults without pinning an exact pose, which a crossfading graph could
    /// not promise anyway.
    ///
    /// Both captures go to gitignored `logs/` for human review; a rendered
    /// frame embeds the user's own assets and is never committed.
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

    /// Writes one capture into gitignored `logs/` for human review. A rendered
    /// frame embeds the user's own game assets and is never committed.
    private static func writePNG(_ pixels: [UInt8], name: String) throws {
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(
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
        ))
        try FrameScreenshot.write(
            image: image, to: PlayerBodyFixture.logsDirectory().appending(path: name)
        )
    }
}
