// Stage timing, early ends, the world time scale, and where the eye goes.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import simd
import Testing

struct CinematicShotPlayerTests {
    private typealias Fixture = ESMFixture

    private static func shot(
        action: UInt32 = 0,
        flags: UInt32 = 0x02,
        multipliers: SIMD3<Float> = [1, 1, 0.1],
        maxTime: Float = 2,
        minTime: Float = 1
    ) throws -> ResolvedRecord<CameraShot> {
        let data = Fixture.u32(action, 0, 2, flags)
            + Fixture.f32(multipliers.x, multipliers.y, multipliers.z, maxTime, minTime, 50)
        let record = try CameraShot(record: Fixture.record("CAMS", fields: [("DATA", data)]))
        return ResolvedRecord(
            id: ResolvedFormID(plugin: "Base.esm", objectID: 0x30), record: record,
            sourcePlugin: "Base.esm"
        )
    }

    @Test func stageWithoutAMeshHoldsTheFallbackClampedToItsTimes() throws {
        #expect(try CinematicStage(shot: Self.shot(maxTime: 0, minTime: 0.5), track: nil)
            .duration == 1.5)
        #expect(try CinematicStage(shot: Self.shot(maxTime: 1, minTime: 0.5), track: nil)
            .duration == 1)
        #expect(try CinematicStage(shot: Self.shot(maxTime: 5, minTime: 3), track: nil)
            .duration == 3)
    }

    @Test func anExitShotWithBothTimesZeroHasNoLength() throws {
        #expect(try CinematicStage(shot: Self.shot(maxTime: 0, minTime: 0), track: nil)
            .duration == 0)
    }

    @Test func stagesPlayInOrderAndFinish() throws {
        var player = try CinematicShotPlayer(stages: [
            CinematicStage(shot: Self.shot(action: 0), track: nil),
            CinematicStage(shot: Self.shot(action: 2), track: nil)
        ])
        #expect(player.remainingSeconds == 3)
        player.advance(realSeconds: 1.6)
        #expect(player.stageIndex == 1)
        player.advance(realSeconds: 1.6)
        #expect(player.isFinished)
        #expect(player.worldTimeScale == 1)
    }

    @Test func earlyEndWaitsForTheMinimum() throws {
        var player = try CinematicShotPlayer(stages: [
            CinematicStage(shot: Self.shot(), track: nil),
            CinematicStage(shot: Self.shot(), track: nil)
        ])
        player.advance(realSeconds: 0.5)
        player.endStageEarly()
        #expect(player.stageIndex == 0)
        player.advance(realSeconds: 0.6)
        player.endStageEarly()
        #expect(player.stageIndex == 1)
    }

    @Test func worldScaleIsGlobalTimesTheSlowerActor() {
        #expect(CinematicTimeScale.worldScale([1, 1, 0.1]) == 0.1)
        #expect(abs(CinematicTimeScale.worldScale([0.4, 0.4, 1]) - 0.4) < 0.0001)
        #expect(CinematicTimeScale.worldScale([0, 0, 0.5]) == 0.5)
        #expect(CinematicTimeScale.worldScale(nil) == 1)
        #expect(CinematicTimeScale.worldScale([1, 1, 0]) == 1)
    }

    @Test func eyeTurnsWithTheAnchorAndLooksAtTheTarget() throws {
        let player = try CinematicShotPlayer(stages: [CinematicStage(
            shot: Self.shot(),
            track: nil
        )])
        let anchors = CinematicAnchors(
            attacker: CinematicAnchor(position: [0, 0, 0], yaw: .pi / 2),
            target: CinematicAnchor(position: [0, 500, 0], yaw: 0)
        )
        let pose = try #require(player.pose(anchors: anchors))
        #expect(simd_distance(pose.eye, [160, -60, 110]) < 0.01)
        #expect(pose.lookAt == [0, 500, 96])
    }
}
