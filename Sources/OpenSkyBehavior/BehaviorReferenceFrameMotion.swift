// Clip travel read from `hkaDefaultAnimatedReferenceFrame`: samples spread evenly
// over the clip, each a position and a heading about `m_up`
// (docs/formats/hka-animation.md).

import Foundation
public import OpenSkyFormatsAnimation
import simd

nonisolated extension HKADefaultAnimatedReferenceFrame {
    /// The frame at `time` seconds, linear between the two nearest samples.
    public func pose(at time: Float) -> HKABonePose? {
        guard let first = samples.first else { return nil }
        var sample = first
        if samples.count > 1, duration > 0 {
            let position = min(max(time / duration, 0), 1) * Float(samples.count - 1)
            let low = min(Int(position), samples.count - 2)
            let amount = position - Float(low)
            sample = samples[low] + (samples[low + 1] - samples[low]) * amount
        }
        let axis = SIMD3(up.x, up.y, up.z)
        let length = simd_length(axis)
        return HKABonePose(
            translation: SIMD3(sample.x, sample.y, sample.z),
            rotation: length > 0
                ? simd_quatf(angle: sample.w, axis: axis / length)
                : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            scale: SIMD3(repeating: 1)
        )
    }

    /// The travel from `start` to `end`, through the clip's end and start when it
    /// wrapped. `window` bounds the played part of the clip.
    public func motion(
        from start: Float, to end: Float, wrapped: Bool, window: ClosedRange<Float>
    ) -> BehaviorRootMotion {
        guard let from = pose(at: start), let to = pose(at: end) else {
            return .identity
        }
        guard
            wrapped,
            let windowEnd = pose(at: window.upperBound),
            let windowStart = pose(at: window.lowerBound)
        else {
            return BehaviorPoseMath.rootMotion(from: from, to: to, isExtracted: true)
        }
        return BehaviorPoseMath.concatenating(
            BehaviorPoseMath.rootMotion(from: from, to: windowEnd, isExtracted: true),
            BehaviorPoseMath.rootMotion(from: windowStart, to: to, isExtracted: true)
        )
    }
}
