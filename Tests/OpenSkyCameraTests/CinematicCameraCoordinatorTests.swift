// A kill cam picks its stages, slows the world while it plays, frames the
// target, and lets go when the last stage ends. A shake fades with distance.

import Foundation
@testable import OpenSkyCamera
import OpenSkyConditions
@testable import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import simd
import Testing

final class FakeCinematicWorld: CinematicCameraWorld {
    var cameraPaths: CameraPathStore?
    var anchors: [ReferenceKey: CinematicAnchor] = [:]
    var playerPosition: SIMD3<Float>? = .zero

    func cameraConditionContext() -> ConditionContext {
        ConditionContext()
    }

    func cameraShotFacts(
        attacker: ReferenceKey,
        target: ReferenceKey?
    ) -> CameraConditionResolution {
        .empty
    }

    func cameraTrack(model: String) -> NIFCameraTrack? {
        nil
    }

    func cinematicAnchor(of key: ReferenceKey) -> CinematicAnchor? {
        anchors[key]
    }

    func startImageSpaceModifier(_ key: ReferenceKey) -> Bool {
        true
    }
}

@MainActor
struct CinematicCameraCoordinatorTests {
    private typealias Fixture = ESMFixture
    static let attacker = ReferenceKey.player
    static let target = ReferenceKey.plugin(name: "base.esm", objectID: 0x900)

    /// One root path with two stages: a slow-motion shot, then a hit shot.
    private static func store() throws -> CameraPathStore {
        func shot(_ formID: UInt32, action: UInt32) -> Data {
            let data = Fixture.u32(action, 0, 2, 0x02) + Fixture.f32(1, 1, 0.5, 2, 1, 50)
            return Fixture.recordBytes("CAMS", formID: formID, fields: [("DATA", data)])
        }
        let path = Fixture.recordBytes("CPTH", formID: 0x40, fields: [
            ("EDID", Fixture.zstring("Kills")), ("ANAM", Fixture.u32(0, 0)), (
                "DATA",
                Fixture.u8(1)
            ),
            ("SNAM", Fixture.u32(0x30)), ("SNAM", Fixture.u32(0x31))
        ])
        return try CameraPathStore(plugins: [("Base.esm", Fixture.plugin(records: [
            shot(0x30, action: 0), shot(0x31, action: 2), path
        ]))])
    }

    private static func world() throws -> FakeCinematicWorld {
        let world = FakeCinematicWorld()
        world.cameraPaths = try store()
        world.anchors[attacker] = CinematicAnchor(position: .zero, yaw: 0)
        world.anchors[target] = CinematicAnchor(position: SIMD3(300, 0, 0), yaw: .pi)
        return world
    }

    @Test func killCamPlaysEachStageSlowedThenLetsGo() throws {
        let world = try Self.world()
        let camera = CinematicCameraCoordinator(world: world)

        #expect(!camera.playKillCam(
            attacker: Self.attacker,
            target: Self.target,
            remainingHostiles: 2
        ))
        #expect(camera.playKillCam(
            attacker: Self.attacker,
            target: Self.target,
            remainingHostiles: 0
        ))
        #expect(camera.player?.stages.count == 2)

        let first = camera.tick(realSeconds: 0.1)
        #expect(first.timeScale == 0.5)
        #expect(first.pose?.lookAt.x == 300)

        let last = camera.tick(realSeconds: CinematicShotPlayer.fallbackStageSeconds * 2)
        #expect(!camera.isPlaying)
        #expect(last == CinematicFrame(pose: nil, shake: .zero, timeScale: 1))
    }

    @Test func forcedKillCamSkipsTheOdds() throws {
        let world = try Self.world()
        var settings = KillCamSettings()
        settings.enabled = false
        let camera = CinematicCameraCoordinator(world: world, settings: settings)
        #expect(camera.playKillCam(
            attacker: Self.attacker, target: Self.target, remainingHostiles: 3, force: true
        ))
    }

    @Test func shakeFadesWithDistanceAndEnds() throws {
        let world = try Self.world()
        let camera = CinematicCameraCoordinator(world: world)

        #expect(!camera.startShake(
            source: SIMD3(CameraShake.falloffDistance * 2, 0, 0),
            strength: 1,
            duration: 1
        ))
        #expect(camera.startShake(source: nil, strength: 1, duration: 1))
        #expect(simd_length(camera.tick(realSeconds: 0.25).shake) > 0)
        #expect(camera.tick(realSeconds: 1).shake == .zero)
        #expect(camera.shake == nil)
    }
}
