// The camera move of one benchmark scene. Points are offsets from the scene's
// origin, so a shot is written once and placed where the scene arrives.

import Foundation
import simd

/// Where the eye stands and where it looks. Yaw 0 looks along +X; positive pitch looks up.
nonisolated public struct BenchmarkCameraPose: Equatable, Sendable {
    public var eye: SIMD3<Float>
    public var yaw: Float
    public var pitch: Float

    public init(eye: SIMD3<Float>, yaw: Float, pitch: Float) {
        self.eye = eye
        self.yaw = yaw
        self.pitch = pitch
    }

    public init(eye: SIMD3<Float>, lookingAt target: SIMD3<Float>) {
        let look = target - eye
        let horizontal = simd_length(SIMD2(look.x, look.y))
        self.init(
            eye: eye,
            yaw: horizontal > .ulpOfOne ? atan2f(look.y, look.x) : 0,
            pitch: atan2f(look.z, max(horizontal, .ulpOfOne))
        )
    }
}

nonisolated public enum BenchmarkShot: Equatable, Sendable {
    /// The eye follows a spline through `path` while it looks along a spline through `focus`.
    case dolly(path: [SIMD3<Float>], focus: [SIMD3<Float>], seconds: Double)
    /// A circle around `center` at `radius` and `height` above it, looking at the center.
    case orbit(
        center: SIMD3<Float>, radius: Float, height: Float,
        startDegrees: Float, sweepDegrees: Float, seconds: Double
    )
    /// A straight flight from `from` to `to`, looking ahead and down by `pitchDegrees`.
    case flyover(from: SIMD3<Float>, to: SIMD3<Float>, pitchDegrees: Float, seconds: Double)
    /// The eye stands still and turns from one heading to another.
    case pan(
        eye: SIMD3<Float>, fromYawDegrees: Float, toYawDegrees: Float,
        pitchDegrees: Float, seconds: Double
    )

    public var seconds: Double {
        switch self {
        case let .dolly(_, _, seconds), let .orbit(_, _, _, _, _, seconds),
             let .flyover(_, _, _, seconds), let .pan(_, _, _, _, seconds):
            seconds
        }
    }

    public var kind: String {
        switch self {
        case .dolly: "dolly"
        case .orbit: "orbit"
        case .flyover: "flyover"
        case .pan: "pan"
        }
    }

    /// The pose `elapsed` seconds in, eased at both ends; `origin` places the offsets.
    public func pose(at elapsed: Double, origin: SIMD3<Float> = .zero) -> BenchmarkCameraPose {
        let progress = Self.ease(seconds > 0 ? Float(min(max(elapsed / seconds, 0), 1)) : 1)
        switch self {
        case let .dolly(path, focus, _):
            return BenchmarkCameraPose(
                eye: origin + Self.spline(path, at: progress),
                lookingAt: origin + Self.spline(focus, at: progress)
            )
        case let .orbit(center, radius, height, start, sweep, _):
            let angle = (start + sweep * progress) * .pi / 180
            let eye = center + SIMD3(cos(angle) * radius, sin(angle) * radius, height)
            return BenchmarkCameraPose(eye: origin + eye, lookingAt: origin + center)
        case let .flyover(from, to, pitch, _):
            let heading = to - from
            return BenchmarkCameraPose(
                eye: origin + from + heading * progress,
                yaw: atan2f(heading.y, heading.x),
                pitch: -pitch * .pi / 180
            )
        case let .pan(eye, fromYaw, toYaw, pitch, _):
            return BenchmarkCameraPose(
                eye: origin + eye,
                yaw: (fromYaw + (toYaw - fromYaw) * progress) * .pi / 180,
                pitch: pitch * .pi / 180
            )
        }
    }

    /// Smoothstep, so a shot starts and stops without a jerk.
    static func ease(_ value: Float) -> Float {
        value * value * (3 - 2 * value)
    }

    /// A uniform Catmull-Rom curve through every point, with the end points repeated.
    static func spline(_ points: [SIMD3<Float>], at progress: Float) -> SIMD3<Float> {
        guard points.count > 1 else { return points.first ?? .zero }
        let scaled = progress * Float(points.count - 1)
        let index = min(Int(scaled), points.count - 2)
        let local = scaled - Float(index)
        let p0 = points[max(index - 1, 0)]
        let p1 = points[index]
        let p2 = points[index + 1]
        let p3 = points[min(index + 2, points.count - 1)]
        let t2 = local * local
        let t3 = t2 * local
        let constant = 2 * p1
        let linear = (p2 - p0) * local
        let quadratic = (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
        let cubic = (3 * p1 - p0 - 3 * p2 + p3) * t3
        return 0.5 * (constant + linear + quadratic + cubic)
    }
}
