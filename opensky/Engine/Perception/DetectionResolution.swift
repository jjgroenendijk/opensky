// The one place a condition asks "does this actor see that one, and how far
// away is it?" (issue #202, roadmap item 16.6), mirroring `ActorStateResolution`
// and, through it, `GlobalResolution` and `QuestResolution`.
//
// Shaped as a resolved snapshot rather than as a live handle for the same reason
// the actor seam is: `ConditionContext` is a nonisolated value a build thread
// may evaluate against, so it cannot reach into `PerceptionRuntime`. The caller
// that *is* on the main actor builds one of these and hands it over.
//
// ## Why this is a second seam and not three more fields on the first
//
// `ActorConditionState` answers questions about *one* actor: its values, its
// death, its hostility. All three functions this seam serves are about a
// *pair* — `GetDetected` and `GetLineOfSight` name a second reference as their
// parameter, and `GetDistance` is meaningless without one. Keying pairs into a
// per-actor table would mean a dictionary inside a dictionary and a run-on that
// silently answers about the wrong side.
//
// Positions ride along here rather than on the actor seam for the same reason:
// `GetDistance` is the only condition function that needs one, it needs two at
// once, and both come from the same pass that produced the pairs.
//
// Documented in docs/formats/conditions.md and docs/engine/detection.md.

import Foundation
import simd

/// Resolved perception for a whole evaluation.
///
/// A value type over two dictionaries: cheap to build, cheap to copy, and
/// unable to go stale mid-evaluation the way a live read could.
nonisolated struct DetectionResolution: Sendable {
    /// No perception at all, which is what a context with no world running
    /// carries. Every detection function is then a reason-tagged false and a
    /// tally bucket rather than a convincing zero.
    static let empty = DetectionResolution()

    private let pairs: [DetectionPairKey: DetectionPairState]
    private let positions: [ReferenceKey: SIMD3<Float>]

    init(
        pairs: [DetectionPairKey: DetectionPairState] = [:],
        positions: [ReferenceKey: SIMD3<Float>] = [:]
    ) {
        self.pairs = pairs
        self.positions = positions
    }

    /// `observer`'s regard for `target`, or nil when the pass tracks no such
    /// pair.
    func pair(observer: ReferenceKey, target: ReferenceKey) -> DetectionPairState? {
        pairs[DetectionPairKey(observer: observer, target: target)]
    }

    /// Where `key` stands, or nil when nothing in this resolution places it.
    func position(of key: ReferenceKey) -> SIMD3<Float>? {
        positions[key]
    }

    /// Distance between two references, or nil when either is unplaced.
    func distance(from first: ReferenceKey, to second: ReferenceKey) -> Float? {
        guard let start = positions[first], let end = positions[second] else { return nil }
        let separation = simd_distance(start, end)
        return separation.isFinite ? separation : nil
    }

    var isEmpty: Bool {
        pairs.isEmpty && positions.isEmpty
    }

    /// Pairs this resolution knows about.
    var pairCount: Int {
        pairs.count
    }
}

extension PerceptionRuntime {
    /// This pass as a condition seam: every tracked pair plus every roster
    /// member's position.
    func resolution() -> DetectionResolution {
        var positions: [ReferenceKey: SIMD3<Float>] = [:]
        for observer in observers {
            positions[observer.key] = observer.feet
        }
        for target in targets {
            positions[target.key] = target.feet
        }
        return DetectionResolution(pairs: pairs, positions: positions)
    }
}
