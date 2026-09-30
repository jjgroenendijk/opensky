// What perception knows about pairs of actors, for conditions: a snapshot the
// main actor builds, like `ActorStateResolution`. A separate seam, because
// `GetDetected`, `GetLineOfSight`, and `GetDistance` are about pairs. Positions
// ride here, because only `GetDistance` needs them.
// See docs/engine/condition-functions.md and docs/engine/detection.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import simd

/// Resolved perception for a whole evaluation.
///
/// A value type over two dictionaries: cheap to build, cheap to copy, and
/// unable to go stale mid-evaluation the way a live read could.
nonisolated public struct DetectionResolution: Sendable {
    /// No perception at all, which is what a context with no world running
    /// carries. Every detection function is then a reason-tagged false and a
    /// tally bucket rather than a convincing zero.
    public static let empty = DetectionResolution()

    private let pairs: [DetectionPairKey: DetectionPairState]
    private let positions: [ReferenceKey: SIMD3<Float>]

    public init(
        pairs: [DetectionPairKey: DetectionPairState] = [:],
        positions: [ReferenceKey: SIMD3<Float>] = [:]
    ) {
        self.pairs = pairs
        self.positions = positions
    }

    /// `observer`'s regard for `target`, or nil when the pass tracks no such
    /// pair.
    public func pair(observer: ReferenceKey, target: ReferenceKey) -> DetectionPairState? {
        pairs[DetectionPairKey(observer: observer, target: target)]
    }

    /// Distance between two references, or nil when either is unplaced.
    public func distance(from first: ReferenceKey, to second: ReferenceKey) -> Float? {
        guard let start = positions[first], let end = positions[second] else { return nil }
        let separation = simd_distance(start, end)
        return separation.isFinite ? separation : nil
    }

    public var isEmpty: Bool {
        pairs.isEmpty && positions.isEmpty
    }

    /// Pairs this resolution knows about.
    public var pairCount: Int {
        pairs.count
    }
}

nonisolated extension DetectionResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    /// The one seam the perception pass comes through, shaped
    /// exactly like the four above. Empty in a context with no world running,
    /// which makes every detection function a reason-tagged false rather than a
    /// convincing "not detected".
    public var detection: DetectionResolution {
        get { self[resolution: DetectionResolution.self] }
        set {
            self[resolution: DetectionResolution.self] = newValue
        }
    }
}
