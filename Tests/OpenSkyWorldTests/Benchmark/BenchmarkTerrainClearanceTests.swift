import Foundation
@testable import OpenSkyWorld
import simd
import Testing

struct BenchmarkTerrainClearanceTests {
    /// The ground climbs one unit per unit east, so a level flight east runs into it.
    private static func slope(x: Float, y _: Float) -> Float? {
        max(x, 0)
    }

    private static var slopeOnly: BenchmarkObstacles {
        BenchmarkObstacles(ground: slope, isBlocked: { _, _ in false })
    }

    @Test func aLevelFlightClimbsOverRisingGround() {
        let shot = BenchmarkShot.flyover(
            from: [0, 0, 500], to: [2000, 0, 500], pitchDegrees: 0, seconds: 8
        )
        var clearance = BenchmarkTerrainClearance()
        var lastZ: Float = 0
        for step in 0 ... 480 {
            let elapsed = Double(step) / 60
            let pose = clearance.lift(
                shot, at: elapsed, origin: .zero, obstacles: Self.slopeOnly
            )
            let ground = Self.slope(x: pose.eye.x, y: 0) ?? 0
            #expect(pose.eye.z >= ground + BenchmarkTerrainClearance.clearance * 0.5)
            #expect(pose.eye.z >= lastZ)
            lastZ = pose.eye.z
        }
    }

    @Test func aShotHighAboveTheGroundStaysAsWritten() {
        let shot = BenchmarkShot.pan(
            eye: [0, 0, 2000], fromYawDegrees: 0, toYawDegrees: 90, pitchDegrees: 0, seconds: 4
        )
        var clearance = BenchmarkTerrainClearance()
        let flat = BenchmarkObstacles(ground: { _, _ in 0 }, isBlocked: { _, _ in false })
        let pose = clearance.lift(shot, at: 1, origin: .zero, obstacles: flat)
        #expect(pose == shot.pose(at: 1))
    }

    @Test func theEyeRisesOverARockInItsPath() {
        // A rock from x 1000 to 2000 reaches 900 high; the flight is written at 500.
        let rock = BenchmarkObstacles(ground: { _, _ in 0 }, isBlocked: { point, radius in
            (1000 - radius ... 2000 + radius).contains(point.x) && point.z - radius < 900
        })
        let shot = BenchmarkShot.flyover(
            from: [0, 0, 500], to: [3000, 0, 500], pitchDegrees: 0, seconds: 6
        )
        var clearance = BenchmarkTerrainClearance()
        for step in 0 ... 360 {
            let pose = clearance.lift(
                shot, at: Double(step) / 60, origin: .zero, obstacles: rock
            )
            #expect(!rock.isBlocked(pose.eye, BenchmarkTerrainClearance.eyeRadius))
        }
    }

    @Test func theEyeRisesOverABigRockItsSphereCannotFeelInside() {
        // Only the rock's skin is felt: a sphere deep inside overlaps no triangle.
        let rock = Self.rock(fromX: 1000, toX: 3000, top: 900)
        let shot = BenchmarkShot.flyover(
            from: [0, 0, 500], to: [4000, 0, 500], pitchDegrees: 0, seconds: 8
        )
        var clearance = BenchmarkTerrainClearance()
        for step in 0 ... 480 {
            let pose = clearance.lift(
                shot, at: Double(step) / 60, origin: .zero, obstacles: rock.obstacles
            )
            #expect(!rock.contains(pose.eye))
        }
    }

    @Test func aShotThatEndsFacingACliffRisesForAnOpenView() {
        let cliff = BenchmarkObstacles(
            ground: { x, _ in x > 400 ? 2000 : 0 }, isBlocked: { _, _ in false }
        )
        let shot = BenchmarkShot.pan(
            eye: [0, 0, 500], fromYawDegrees: 0, toYawDegrees: 0, pitchDegrees: 0, seconds: 4
        )
        var clearance = BenchmarkTerrainClearance()
        let pose = clearance.lift(shot, at: 4, origin: .zero, obstacles: cliff)
        #expect(pose.eye.z >= 2000)
    }

    /// A solid block over the x range, felt only at its faces and by lines through it.
    private static func rock(
        fromX low: Float, toX high: Float, top: Float
    ) -> (obstacles: BenchmarkObstacles, contains: (SIMD3<Float>) -> Bool) {
        let contains: (SIMD3<Float>) -> Bool = { point in
            (low ... high).contains(point.x) && point.z < top
        }
        let skin: (SIMD3<Float>, Float) -> Bool = { point, radius in
            guard point.z - radius < top else { return false }
            return abs(point.x - low) < radius || abs(point.x - high) < radius
                || ((low ... high).contains(point.x) && point.z + radius > top)
        }
        let crosses: (SIMD3<Float>, SIMD3<Float>) -> Bool = { start, end in
            (0 ... 32).contains { part in contains(start + (end - start) * Float(part) / 32) }
        }
        let obstacles = BenchmarkObstacles(
            ground: { _, _ in 0 }, isBlocked: skin, crosses: crosses
        )
        return (obstacles, contains)
    }

    @Test func theLiftShrinksSlowlyAfterARidge() {
        let raise = BenchmarkTerrainClearance.step(1000, toward: 0)
        #expect(raise == 1000 - BenchmarkTerrainClearance.sinkPerStep)
        #expect(BenchmarkTerrainClearance.step(nil, toward: 50) == 50)
        #expect(BenchmarkTerrainClearance.step(70, toward: nil) == 70)
    }
}
