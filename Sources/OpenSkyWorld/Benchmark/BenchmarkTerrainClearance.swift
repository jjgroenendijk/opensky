// Keeps an exterior shot's eye out of the ground, rocks, and buildings. The shots
// are written as heights above one origin, and the world along a path rises past them.

import Foundation
import simd

/// What the clearance reads from the world: the ground height under a point, whether
/// a sphere overlaps static collision, and whether a straight line crosses it.
nonisolated struct BenchmarkObstacles {
    var ground: (Float, Float) -> Float?
    var isBlocked: (SIMD3<Float>, Float) -> Bool
    var crosses: (SIMD3<Float>, SIMD3<Float>) -> Bool = { _, _ in false }
}

nonisolated struct BenchmarkTerrainClearance {
    /// The least height of the eye above the ground under it.
    static let clearance: Float = 300
    /// The eye's sphere stays this far from rocks, walls, and roofs.
    static let eyeRadius: Float = 80
    /// The eye keeps this much open view ahead, so a shot never ends against a cliff.
    static let openView: Float = 600
    /// A blocked eye rises in these steps, up to `maximumRise` over the written height.
    static let riseStep: Float = 100
    static let maximumRise: Float = 4000
    /// The eye also clears what it reaches this far ahead, so it climbs before
    /// a hill or a rock instead of cutting into it.
    static let lookAheadSeconds: [Double] = [0.5, 1, 1.5, 2]
    /// Each step closes this part of the gap to a larger lift.
    static let climbRate: Float = 0.12
    /// Each step the lift shrinks at most this far, so the eye eases down after a ridge.
    static let sinkPerStep: Float = 6

    /// How far the eye is raised over its written height, eased between steps.
    private var raise: Float?
    /// The last eye shown. A sphere deep inside a large rock touches no triangle,
    /// so the line from here to the next eye catches the entry instead.
    private var lastEye: SIMD3<Float>?

    /// The pose with its eye raised clear. The view direction stays.
    mutating func lift(
        _ shot: BenchmarkShot, at elapsed: Double, origin: SIMD3<Float>,
        obstacles: BenchmarkObstacles
    ) -> BenchmarkCameraPose {
        var pose = shot.pose(at: elapsed, origin: origin)
        let nowEye = Self.clear(
            pose, from: lastEye, groundMargin: Self.clearance * 0.5, obstacles
        )
        var previous = nowEye
        let ahead = Self.lookAheadSeconds.map { offset in
            let future = shot.pose(at: elapsed + offset, origin: origin)
            previous = Self.clear(future, from: previous, groundMargin: Self.clearance, obstacles)
            return previous.z - future.eye.z
        }
        let now = nowEye.z - pose.eye.z
        raise = Self.step(raise, toward: (ahead + [now]).max())
        pose.eye.z += max(raise ?? 0, now)
        lastEye = pose.eye
        return pose
    }

    /// The pose's eye at the lowest height at or above it that clears the ground by
    /// `groundMargin`, touches nothing, keeps an open view, and is reached from `previous`.
    static func clear(
        _ pose: BenchmarkCameraPose, from previous: SIMD3<Float>?, groundMargin: Float,
        _ obstacles: BenchmarkObstacles
    ) -> SIMD3<Float> {
        let point = pose.eye
        let ground = obstacles.ground(point.x, point.y).map { $0 + groundMargin }
        var eye = SIMD3(point.x, point.y, max(point.z, ground ?? point.z))
        let limit = point.z + maximumRise
        let ahead = SIMD3(cosf(pose.yaw), sinf(pose.yaw), 0) * openView
        while
            eye.z < limit, obstacles.isBlocked(eye, eyeRadius)
            || previous.map({ obstacles.crosses($0, eye) }) == true
            || isViewBlocked(from: eye, ahead: ahead, obstacles)
        {
            eye.z += riseStep
        }
        return eye
    }

    /// Something stands in the level line of sight within `openView`.
    static func isViewBlocked(
        from eye: SIMD3<Float>, ahead: SIMD3<Float>, _ obstacles: BenchmarkObstacles
    ) -> Bool {
        let rising = [Float(0.25), 0.5, 0.75, 1].contains { part in
            let point = eye + ahead * part
            return (obstacles.ground(point.x, point.y) ?? -.infinity) > point.z
        }
        return rising || obstacles.crosses(eye, eye + ahead)
    }

    static func step(_ current: Float?, toward target: Float?) -> Float? {
        guard let target else { return current }
        guard let current else { return target }
        return target > current
            ? current + (target - current) * climbRate
            : max(target, current - sinkPerStep)
    }
}
