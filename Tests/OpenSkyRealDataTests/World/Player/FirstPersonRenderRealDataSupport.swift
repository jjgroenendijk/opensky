// Helpers for `FirstPersonRenderRealDataTests`: driving the bridge, placing the
// rigs, and turning a rendered texture into pixels and a capture in `.logs/`.

import CoreGraphics
import Foundation
import Metal
import MetalKit
import OpenSkyBehavior
import OpenSkyCombat
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

extension FirstPersonRenderRealDataTests {
    // MARK: - Driving

    /// Steps the bridge once at a fixed capsule pose. Both graphs advance:
    /// there is one `plan` call and it feeds both (LocomotionBridgeFirstPerson).
    static func drive(
        _ assembled: PlayerBodyFixture.Assembled,
        feet: SIMD3<Float>,
        input: CameraInput
    ) {
        assembled.bridge.acceptFrame(input)
        _ = assembled.bridge.plan(LocomotionStepState(
            feetPosition: feet,
            verticalVelocity: 0,
            isGrounded: true,
            yaw: 0,
            dt: WalkController.fixedTimeStep
        ))
    }

    /// `iRightHandType` for fists and for a one-handed sword.
    static let fistsHandType: Int32 = 0
    static let swordHandType: Int32 = 1

    /// Draws the weapon the way the melee runtime does, then steps two seconds so the
    /// equip clip ends in the drawn idle.
    static func drawWeapon(
        _ assembled: PlayerBodyFixture.Assembled,
        feet: SIMD3<Float>,
        handType: Int32
    ) {
        assembled.bridge.write(.int(handType), to: CombatGraphNames.rightHandType)
        assembled.bridge.raise(CombatGraphNames.weaponDraw)
        assembled.bridge.raise(CombatGraphNames.weapEquip)
        for _ in 0 ..< 240 {
            drive(assembled, feet: feet, input: CameraInput(dt: 1.0 / 120))
        }
    }

    @MainActor
    static func place(
        _ assembled: PlayerBodyFixture.Assembled,
        renderer: Renderer,
        feet: SIMD3<Float>
    ) {
        assembled.body.place(feetPosition: feet, yaw: renderer.freeFlyCamera.yaw)
        assembled.body.animation.update(at: 0)
        assembled.arms.animation.update(at: 0)
        assembled.arms.place(
            eyePosition: feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: renderer.freeFlyCamera.yaw,
            pitch: renderer.freeFlyCamera.pitch
        )
    }

    /// Puts the eye where walk mode puts it, looking level — the same pose
    /// `Renderer.advanceCamera` produces, so the capture is what the app shows.
    @MainActor
    static func frameFirstPerson(_ renderer: Renderer, feet: SIMD3<Float>) {
        renderer.freeFlyCamera = FreeFlyCamera(
            position: feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
        renderer.setMovementMode(.walk)
    }

    static func droppedPieces(_ rig: PlayerFirstPersonRig) -> Int {
        rig.assembly.skips.count {
            guard case let .appearance(skip) = $0.subject else { return false }
            return skip.reason == .noFirstPersonModel
        }
    }

    // MARK: - Rendering

    @MainActor
    static func renderer(
        device: MTLDevice,
        scene: CellScene,
        bounds: (min: SIMD3<Float>, max: SIMD3<Float>)
    ) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: size, height: size), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(
            view: view,
            scene: scene.renderScene,
            camera: SceneCamera.framing(bounds: bounds)
        )
    }

    @MainActor
    static func frame(_ renderer: Renderer) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(width: size, height: size)
        return RenderedPixels.read(texture)
    }

    static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        RenderedPixels.changedCount(lhs, rhs)
    }

    /// Writes one square capture into gitignored `.logs/`; the frame embeds game assets.
    static func writePNG(_ pixels: [UInt8], name: String, size: Int = size) throws {
        try RenderedPixels.writePNG(
            pixels, width: size, height: size,
            to: PlayerBodyFixture.logsDirectory().appending(path: name)
        )
    }
}
