// The lockpicking menu's 3D lock from the install: the lock, the shiv, and the pick
// drawn in the menu scene at several pick angles and lock turns. Frames and the
// report go to `.logs/lockpicking-lock/`.
// Run with `make test-real T='LockpickingLockRenderRealDataTests'`.

import Foundation
import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyRendering
@testable import OpenSkyRenderResources
import OpenSkyTagsTesting
import OpenSkyWorld
import Testing

@Suite(.tags(.gpu))
struct LockpickingLockRenderRealDataTests {
    private static let width = 1280
    private static let height = 720

    private static let frames: [String: LockpickingLockPose] = [
        "intro": pose(seconds: 0.3), "rest": pose(), "pick-left": pose(angle: -60),
        "pick-right": pose(angle: 60), "half-turn": pose(turn: 0.5), "open": pose(turn: 1)
    ]

    private static func pose(
        angle: Float = 0, turn: Float = 0, seconds: Float = 3
    ) -> LockpickingLockPose {
        LockpickingLockPose(
            pickSeconds: seconds, lockSeconds: seconds, pickAngle: angle, lockRotation: turn,
            isStraining: false
        )
    }

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func theInstallsLockDrawsAndFollowsThePickAndTheTurn() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let device = try #require(RealDataEnvironment.device)
        let source = LockpickingLockSource(
            fileSystem: VirtualFileSystem(root: root),
            immediate: true
        )
        let models = try #require(source.models(device: device), "\(source.failure ?? "")")
        let session = try RenderedPixels.offscreenSession(
            device: device, width: Self.width, height: Self.height
        )
        let renderer = session.renderer
        let logs = try RepositoryLogs.createdDirectory("lockpicking-lock")
        renderer.setMenuScene(nil)
        let empty = try RenderedPixels.renderFrame(renderer, width: Self.width, height: Self.height)
        var pixels: [String: [UInt8]] = [:]
        var lines = ["[INFO] open at \(models.openSeconds) s of Rotate"]
        for (name, pose) in Self.frames.sorted(by: { $0.key < $1.key }) {
            let scene = LockpickingLockSource.scene(pose, models: models)
            renderer.setMenuScene(scene)
            let frame = try RenderedPixels.renderFrame(
                renderer, width: Self.width, height: Self.height
            )
            try FrameScreenshot.write(
                texture: frame.texture,
                to: logs.appending(path: "\(name).png")
            )
            pixels[name] = frame.pixels
            let drawn = RenderedPixels.changedCount(empty.pixels, frame.pixels)
            lines.append("[INFO] \(name): \(scene.draws.count) draws, \(drawn) pixels drawn")
            #expect(drawn > Self.width * Self.height / 50, "\(name) drew \(drawn) pixels")
        }
        renderer.setMenuScene(nil)
        for (lhs, rhs) in [("rest", "pick-left"), ("rest", "pick-right"), ("rest", "open")] {
            let changed = try RenderedPixels.changedCount(
                #require(pixels[lhs]),
                #require(pixels[rhs])
            )
            lines.append("[INFO] \(lhs) to \(rhs): \(changed) pixels changed")
            #expect(changed > 500, "\(rhs) looks like \(lhs)")
        }
        #expect(models.openSeconds > 0)
        try lines.joined(separator: "\n").write(
            to: logs.appending(path: "report.log"), atomically: true, encoding: .utf8
        )
    }
}
