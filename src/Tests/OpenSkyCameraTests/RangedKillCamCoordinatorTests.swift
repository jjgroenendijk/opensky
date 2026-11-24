// A ranged kill cam follows the projectile until its impact, ends at its time limits,
// and keeps the target's death from starting a second kill cam.

import Foundation
@testable import OpenSkyCamera
import OpenSkyConditions
@testable import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import simd
import Testing

final class FakeRangedCinematicWorld: CinematicCameraWorld {
    var cameraPaths: CameraPathStore?
    var anchors: [ReferenceKey: CinematicAnchor] = [:]
    var projectiles: [Int: CinematicAnchor] = [:]
    var targetIsDead = false
    var playerPosition: SIMD3<Float>? = .zero

    func cameraConditionContext() -> ConditionContext {
        ConditionContext(functions: .standard)
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

    func cinematicProjectileAnchor(_ id: Int) -> CinematicAnchor? {
        projectiles[id]
    }

    func cinematicTargetIsDead(_ key: ReferenceKey) -> Bool {
        targetIsDead
    }
}

@MainActor
struct RangedKillCamCoordinatorTests {
    private typealias Fixture = ESMFixture
    static let target = ReferenceKey.plugin(name: "base.esm", objectID: 0x900)

    /// One long stage placed on the projectile and looking at the target. Its min time
    /// of 30 s outlasts both time limits.
    private static func world() throws -> FakeRangedCinematicWorld {
        let shot = Fixture.recordBytes("CAMS", formID: 0x30, fields: [
            ("DATA", Fixture.u32(1, 1, 2, 0) + Fixture.f32(1, 1, 0.5, 0, 30, 50))
        ])
        let path = Fixture.recordBytes("CPTH", formID: 0x40, fields: [
            ("EDID", Fixture.zstring("Arrows")), ("ANAM", Fixture.u32(0, 0)),
            ("DATA", Fixture.u8(1)), ("SNAM", Fixture.u32(0x30))
        ])
        let world = FakeRangedCinematicWorld()
        world.cameraPaths = try CameraPathStore(plugins: [
            ("Base.esm", Fixture.plugin(records: [shot, path]))
        ])
        world.anchors[.player] = CinematicAnchor(position: .zero, yaw: 0)
        world.anchors[target] = CinematicAnchor(position: SIMD3(900, 0, 0), yaw: .pi)
        world.projectiles[7] = CinematicAnchor(position: SIMD3(100, 0, 50), yaw: 0, focusHeight: 0)
        return world
    }

    @Test func theCameraFollowsTheProjectileUntilItsImpact() throws {
        let world = try Self.world()
        let camera = CinematicCameraCoordinator(world: world)
        #expect(camera.playRangedKillCam(projectile: 7, target: Self.target))
        #expect(camera.projectile == 7)
        let flying = camera.tick(realSeconds: 0.05)
        #expect(flying.pose?.eye.x ?? 0 > 0)

        world.projectiles[7] = nil
        _ = camera.tick(realSeconds: 0.05)
        #expect(camera.projectile == nil)
        #expect(camera.isPlaying)
    }

    @Test func theShotEndsAfterSixSecondsWhileTheTargetLives() throws {
        let world = try Self.world()
        let camera = CinematicCameraCoordinator(world: world)
        camera.playRangedKillCam(projectile: 7, target: Self.target)
        for _ in 0 ..< 23 {
            _ = camera.tick(realSeconds: 0.25)
        }
        #expect(camera.isPlaying)
        _ = camera.tick(realSeconds: 0.25)
        #expect(!camera.isPlaying)
    }

    @Test func aDeadTargetKeepsTheShotUntilTwentySeconds() throws {
        let world = try Self.world()
        world.targetIsDead = true
        let camera = CinematicCameraCoordinator(world: world)
        camera.playRangedKillCam(projectile: 7, target: Self.target)
        for _ in 0 ..< 79 {
            _ = camera.tick(realSeconds: 0.25)
        }
        #expect(camera.isPlaying)
        _ = camera.tick(realSeconds: 0.25)
        #expect(!camera.isPlaying)
    }

    @Test func theDeathOfADecidedTargetStartsNoSecondKillCam() throws {
        let world = try Self.world()
        let camera = CinematicCameraCoordinator(world: world)
        #expect(!camera.killCamWasDecided(for: Self.target))
        camera.playRangedKillCam(projectile: 7, target: Self.target)
        #expect(camera.killCamWasDecided(for: Self.target))
        #expect(!camera.killCamWasDecided(for: Self.target))
    }

    @Test func aRunningKillCamIsNotReplaced() throws {
        let world = try Self.world()
        let camera = CinematicCameraCoordinator(world: world)
        camera.playKillCam(
            attacker: .player,
            target: Self.target,
            remainingHostiles: 0,
            force: true
        )
        #expect(!camera.playRangedKillCam(projectile: 7, target: Self.target))
        #expect(camera.projectile == nil)
        #expect(camera.killCamWasDecided(for: Self.target))
    }

    @Test func theLimitsAreTwentySecondsOrSixWhileAlive() {
        #expect(!RangedKillCamLimits.ends(elapsed: 5.9, targetIsDead: false))
        #expect(RangedKillCamLimits.ends(elapsed: 6, targetIsDead: false))
        #expect(!RangedKillCamLimits.ends(elapsed: 19.9, targetIsDead: true))
        #expect(RangedKillCamLimits.ends(elapsed: 20, targetIsDead: true))
    }

    @Test func zeroActorMultipliersFallBackToSixAndOne() {
        #expect(CinematicTimeScale.worldScale([0, 0.5, 1]) == 0.5)
        #expect(CinematicTimeScale.worldScale([0.4, 0, 1]) == 0.4)
        #expect(CinematicTimeScale.worldScale([-1, -1, 0.33]) == 0.33)
    }
}
