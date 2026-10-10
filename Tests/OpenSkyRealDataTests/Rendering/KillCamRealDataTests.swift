// A bow kill cam over the real camera paths and camera meshes, played through
// a renderer to the end: the world clock slows while it plays, the view moves,
// and the player's own view comes back. The report goes to `.logs/kill-cam.log`.
// Run with `make test-real T='KillCamRealDataTests'`.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyGameData
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import simd
import Testing

@MainActor
private final class RealKillCamWorld: CinematicCameraWorld {
    let renderer: Renderer
    let fileSystem: VirtualFileSystem
    let cameraPaths: CameraPathStore?
    let bow: Weapon?
    var playerPosition: SIMD3<Float>? = .zero
    private(set) var lowestTimeScale: Float = 1
    private(set) var posedFrames = 0
    private(set) var tracks: [String: Bool] = [:]

    init(renderer: Renderer, fileSystem: VirtualFileSystem, paths: CameraPathStore, bow: Weapon?) {
        self.renderer = renderer
        self.fileSystem = fileSystem
        cameraPaths = paths
        self.bow = bow
    }

    func cameraConditionContext() -> ConditionContext {
        ConditionContext()
    }

    func cameraShotFacts(
        attacker: ReferenceKey,
        target: ReferenceKey?
    ) -> CameraConditionResolution {
        CameraShotFacts
            .resolution(weapon: bow, targetBase: nil, targetDistance: 900, yaw: 0) { _ in 1000 }
    }

    func cameraTrack(model: String) -> NIFCameraTrack? {
        let track =
            try? NIFCameraTrack(file: NIFFile(data: fileSystem
                    .contents(forPath: "meshes\\" + model)))
        tracks[model] = track != nil
        return track
    }

    func cinematicAnchor(of key: ReferenceKey) -> CinematicAnchor? {
        key == .player
            ? CinematicAnchor(position: .zero, yaw: 0)
            : CinematicAnchor(position: SIMD3(900, 0, 0), yaw: .pi)
    }

    func applyCinematicFrame(pose: CinematicCameraPose?, shake: SIMD3<Float>, timeScale: Float) {
        lowestTimeScale = min(lowestTimeScale, timeScale)
        posedFrames += pose == nil ? 0 : 1
        renderer.worldTimeScale = timeScale
        renderer.setCinematicCamera(pose, shakeOffset: shake)
    }

    func startImageSpaceModifier(_ key: ReferenceKey) -> Bool {
        true
    }
}

@Suite(.tags(.gpu))
struct KillCamRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func aBowKillSlowsTheWorldMovesTheViewAndGivesItBack() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let device = try #require(RealDataEnvironment.device)
        let plugins = try VanillaMasters.load(root: root)
        let renderer = try RenderedPixels.offscreenRenderer(device: device, width: 320, height: 180)
        renderer.freeFlyCamera = FreeFlyCamera(position: SIMD3(0, 0, 120), yaw: 0, pitch: 0)
        let before = renderer.freeFlyCamera
        let world = RealKillCamWorld(
            renderer: renderer,
            fileSystem: VirtualFileSystem(root: root),
            paths: CameraPathStore(plugins: plugins),
            bow: CameraShotSelectionRealDataTests.firstBow(plugins: plugins)
        )
        let camera = CinematicCameraCoordinator()
        camera.attach(world: world)
        let target = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_A67C)
        #expect(camera.playKillCam(
            attacker: .player,
            target: target,
            remainingHostiles: 0,
            force: true
        ))
        let stages = camera.player?.stages.map { $0.shot.record.editorID ?? "?" } ?? []
        var moved = false
        var frames = 0
        while camera.isPlaying, frames < 60 * 30 {
            camera.tick(realSeconds: 1.0 / 60)
            moved = moved || simd_distance(renderer.freeFlyCamera.position, before.position) > 1
            frames += 1
        }
        camera.tick(realSeconds: 1.0 / 60)
        let after = renderer.freeFlyCamera
        let lines = [
            "[INFO] bow \(world.bow?.fields.editorID ?? "none"): \(camera.lastOutcome ?? "-")",
            "[INFO] path \(camera.lastSelection.path?.record.editorID ?? "none"), stages \(stages)",
            "[INFO] camera tracks \(world.tracks)",
            "[INFO] \(frames) frames, \(world.posedFrames) posed, "
                + "lowest world time scale \(world.lowestTimeScale)",
            "[INFO] view moved \(moved), back at \(after.position) yaw \(after.yaw) "
                + "(was \(before.position))"
        ]
        try lines.joined(separator: "\n").write(
            to: RepositoryLogs.directory().appending(path: "kill-cam.log"), atomically: true,
            encoding: .utf8
        )
        #expect(world.lowestTimeScale < 1, "\(lines)")
        #expect(moved)
        #expect(!camera.isPlaying)
        #expect(after.position == before.position && after.yaw == before.yaw)
        #expect(renderer.worldTimeScale == 1)
    }
}
