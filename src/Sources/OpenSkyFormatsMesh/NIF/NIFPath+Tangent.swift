// The direction and the bend of an `NiPathInterpolator` path at a fraction of its length,
// with the smoothing that blends a segment's ends into its neighbours
// (docs/formats/nif-controllers.md#node-controller-rules).

import Foundation
import simd

nonisolated extension NIFPath {
    /// The step, as a path fraction, used to measure a direction or a bend.
    static let measureStep: Float = 0.001
    /// Samples used to find the path's largest bend.
    static let curvatureSamples = 128

    /// The segment between two path points that holds `fraction`, and how far along it.
    func segment(atFraction fraction: Float) -> (index: Int, local: Float)? {
        guard points.count > 1, let first = points.first, let last = points.last else {
            return nil
        }
        let fraction = simd_clamp(fraction, 0, 1)
        if hasConstantVelocity {
            let lengths = zip(points, points.dropFirst()).map { simd_distance($0.value, $1.value) }
            var remaining = lengths.reduce(0, +) * fraction
            for (index, length) in lengths.enumerated() {
                if remaining <= length || index == lengths.count - 1 {
                    return (index, length > 0 ? simd_clamp(remaining / length, 0, 1) : 0)
                }
                remaining -= length
            }
            return nil
        }
        let time = first.time + (last.time - first.time) * fraction
        for index in 0 ..< points.count - 1 {
            let start = points[index].time
            let end = points[index + 1].time
            if time <= end || index == points.count - 2 {
                return (index, end > start ? simd_clamp((time - start) / (end - start), 0, 1) : 0)
            }
        }
        return nil
    }

    /// The unit direction of travel at `fraction`. With smoothing s and the allow-flip flag,
    /// the first and last s of each segment lean toward the neighbour's direction.
    public func tangent(atFraction fraction: Float) -> SIMD3<Float>? {
        guard let base = rawTangent(atFraction: fraction) else { return nil }
        let smoothing = interpolator.smoothing
        guard
            interpolator.allowsFlip, smoothing > 0,
            let segment = segment(atFraction: fraction)
        else { return base }
        let step = Self.measureStep
        var neighbour: SIMD3<Float>?
        var weight: Float = 0
        if segment.local <= smoothing, segment.index > 0 {
            neighbour = rawTangent(atFraction: fraction - segment.local * span(segment) - step)
            weight = (smoothing - segment.local) * 0.5 / smoothing
        } else if segment.local >= 1 - smoothing, segment.index < points.count - 2 {
            let toEnd = (1 - segment.local) * span(segment)
            neighbour = rawTangent(atFraction: fraction + toEnd + step)
            weight = (smoothing - (1 - segment.local)) * 0.5 / smoothing
        }
        guard let neighbour, weight > 0 else { return base }
        let mixed = simd_mix(base, neighbour, SIMD3(repeating: weight))
        return simd_length_squared(mixed) > 1e-12 ? simd_normalize(mixed) : base
    }

    /// The signed bend about +Z at `fraction`: the change of heading per unit of length.
    public func curvature(atFraction fraction: Float) -> Float {
        let step = Self.measureStep * 5
        guard
            let behind = tangent(atFraction: fraction - step),
            let ahead = tangent(atFraction: fraction + step),
            let from = position(atFraction: fraction - step),
            let to = position(atFraction: fraction + step)
        else { return 0 }
        let distance = simd_distance(from, to)
        guard distance > 1e-6 else { return 0 }
        return NIFPathOrientation.headingChange(from: behind, to: ahead) / distance
    }

    /// The largest bend along the path, the scale a bank is measured against.
    func largestCurvature() -> Float {
        (0 ... Self.curvatureSamples).reduce(0) { largest, sample in
            max(largest, abs(curvature(atFraction: Float(sample) / Float(Self.curvatureSamples))))
        }
    }

    /// The share of the whole path one segment covers, as a path fraction.
    private func span(_ segment: (index: Int, local: Float)) -> Float {
        let lengths = zip(points, points.dropFirst()).map { simd_distance($0.value, $1.value) }
        if hasConstantVelocity {
            let total = lengths.reduce(0, +)
            return total > 0 ? lengths[segment.index] / total : 0
        }
        guard let first = points.first, let last = points.last, last.time > first.time else {
            return 0
        }
        return (points[segment.index + 1].time - points[segment.index].time)
            / (last.time - first.time)
    }

    private func rawTangent(atFraction fraction: Float) -> SIMD3<Float>? {
        let step = Self.measureStep
        guard
            let behind = position(atFraction: simd_clamp(fraction - step, 0, 1)),
            let ahead = position(atFraction: simd_clamp(fraction + step, 0, 1))
        else { return nil }
        let direction = ahead - behind
        return simd_length_squared(direction) > 1e-12 ? simd_normalize(direction) : nil
    }
}
