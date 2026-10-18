// Camera paths of the benchmark shots, checked at their ends and middles.

@testable import OpenSkyWorld
import simd
import Testing

struct BenchmarkShotTests {
    private func close(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, tolerance: Float = 0.01) -> Bool {
        simd_distance(lhs, rhs) < tolerance
    }

    @Test func aDollyStartsAndEndsOnItsPathPoints() {
        let shot = BenchmarkShot.dolly(
            path: [SIMD3(0, 0, 100), SIMD3(500, 0, 150), SIMD3(1000, 200, 200)],
            focus: [SIMD3(2000, 0, 0)], seconds: 10
        )
        let origin = SIMD3<Float>(10, 20, 30)
        #expect(close(shot.pose(at: 0, origin: origin).eye, SIMD3(10, 20, 130)))
        #expect(close(shot.pose(at: 10, origin: origin).eye, SIMD3(1010, 220, 230)))
        #expect(close(shot.pose(at: 99, origin: origin).eye, SIMD3(1010, 220, 230)))
    }

    @Test func anOrbitLooksAtItsCentreFromItsRadius() {
        let shot = BenchmarkShot.orbit(
            center: SIMD3(0, 0, 0), radius: 1000, height: 0, startDegrees: 90, sweepDegrees: 180,
            seconds: 8
        )
        let start = shot.pose(at: 0)
        #expect(close(start.eye, SIMD3(0, 1000, 0), tolerance: 0.1))
        #expect(abs(start.yaw - -Float.pi / 2) < 1e-4, "looks south, back at the centre")
        #expect(close(shot.pose(at: 8).eye, SIMD3(0, -1000, 0), tolerance: 0.1))
    }

    @Test func aFlyoverMovesInAStraightLineAndLooksDown() {
        let shot = BenchmarkShot.flyover(
            from: SIMD3(0, 0, 0),
            to: SIMD3(0, 1000, 0),
            pitchDegrees: 30,
            seconds: 4
        )
        let middle = shot.pose(at: 2)
        #expect(close(middle.eye, SIMD3(0, 500, 0)))
        #expect(abs(middle.yaw - .pi / 2) < 1e-5)
        #expect(abs(middle.pitch - -Float.pi / 6) < 1e-5)
    }

    @Test func aPanTurnsWithoutMoving() {
        let shot = BenchmarkShot.pan(
            eye: SIMD3(0, 0, 120),
            fromYawDegrees: 0,
            toYawDegrees: 180,
            pitchDegrees: 0,
            seconds: 6
        )
        #expect(shot.pose(at: 0).yaw == 0)
        #expect(abs(shot.pose(at: 6).yaw - .pi) < 1e-5)
        #expect(shot.pose(at: 3).eye == SIMD3(0, 0, 120))
        #expect(shot.kind == "pan" && shot.seconds == 6)
    }

    @Test func theEaseHoldsItsEndsAndItsMiddle() {
        #expect(BenchmarkShot.ease(0) == 0)
        #expect(BenchmarkShot.ease(1) == 1)
        #expect(BenchmarkShot.ease(0.5) == 0.5)
        #expect(BenchmarkShot.ease(0.1) < 0.1, "starts slower than linear")
    }

    @Test func aLookAtPoseUpIsPositivePitch() {
        let pose = BenchmarkCameraPose(eye: .zero, lookingAt: SIMD3(100, 0, 100))
        #expect(abs(pose.pitch - .pi / 4) < 1e-5)
        #expect(pose.yaw == 0)
    }

    @Test func everyCatalogSceneHasAUniqueIdAndAMeasurableShot() {
        let ids = BenchmarkTour.scenes.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(BenchmarkTour.scenes.allSatisfy { $0.shot.seconds > 0 })
        #expect(Set(BenchmarkTour.scenes.map(\.group)) == Set(BenchmarkSceneGroup.allCases))
        #expect(BenchmarkTour.scenes.filter { $0.group == .dlc }
            .allSatisfy { $0.requiredPlugin != nil })
    }
}
