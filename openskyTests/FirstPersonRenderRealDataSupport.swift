// Helpers for the first-person arms render check (issue #190), split out of
// `FirstPersonRenderRealDataTests.swift` for the file and type size limits.
// Driving the bridge, placing the rigs, and turning a rendered texture into
// pixels and into a gitignored capture.

import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalKit
@testable import opensky
import simd
import Testing
import UniformTypeIdentifiers

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

    static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count, !lhs.isEmpty else {
            return max(lhs.count, rhs.count) / 4
        }
        var changed = 0
        for pixel in stride(from: 0, to: lhs.count, by: 4)
            where Array(lhs[pixel ..< pixel + 4]) != Array(rhs[pixel ..< pixel + 4])
        {
            changed += 1
        }
        return changed
    }

    /// Writes one capture into gitignored `logs/`. Never committed: the frame
    /// embeds the user's own game assets.
    static func writePNG(_ pixels: [UInt8], name: String) throws {
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
            ),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            )
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
