// What the perception pass shows a person (issue #202, roadmap item 16.6).
//
// Flat values rather than a live handle on the runtime, for the reason every
// other readout in this engine is: the panel that consumes them arrives with
// the M16 gate (issue #203) and must not be able to reach past what it was
// given, and a value can be asserted on in a test with no window.
//
// The issue names the panel line this feeds — a per-selected-actor readout of
// state, level and last-seen position, under the accessibility identifier
// `DetectionStatsLabel`. `summaryLine` below *is* that line, so the panel
// prints one string rather than re-deriving a format the tests would then have
// to know about twice.
//
// Documented in docs/engine/detection.md.

import Foundation
import simd

/// One observer's regard for one target, as a panel or a transcript shows it.
nonisolated struct DetectionPairReadout: Equatable, Sendable {
    let observer: ReferenceKey
    let observerName: String
    let target: ReferenceKey
    let targetName: String
    let state: DetectionState
    /// Accumulated awareness, 0 through 100.
    let level: Float
    /// The detection value the last evaluation produced.
    let detectionValue: Float
    let soundFactor: Float
    let visualFactor: Float
    let distance: Float
    let hasLineOfSight: Bool
    let isInViewCone: Bool
    /// Where the target was last perceived, or nil when nothing is remembered.
    let lastKnownPosition: SIMD3<Float>?

    /// The `DetectionStatsLabel` line: state, level, and last-seen position.
    var summaryLine: String {
        let seen = lastKnownPosition.map {
            String(format: "last seen (%.0f, %.0f, %.0f)", $0.x, $0.y, $0.z)
        } ?? "nothing remembered"
        return String(
            format: "%@ -> %@: %@, level %.0f, value %.1f, %.0f units, %@, %@",
            observerName,
            targetName,
            state.rawValue,
            level,
            detectionValue,
            distance,
            hasLineOfSight ? (isInViewCone ? "in sight" : "out of cone") : "blocked",
            seen
        )
    }
}

/// The whole pass as one value: what it tracked, what it cost, and what it
/// dropped.
nonisolated struct PerceptionReadout: Equatable, Sendable {
    let pairs: [DetectionPairReadout]
    let observerCount: Int
    let targetCount: Int
    /// Pairs the cap refused to track, so a truncated list never reads as a
    /// complete one.
    let droppedPairCount: Int
    let lineOfSightQueryCount: Int
    let stepCount: Int

    static let empty = PerceptionReadout(
        pairs: [],
        observerCount: 0,
        targetCount: 0,
        droppedPairCount: 0,
        lineOfSightQueryCount: 0,
        stepCount: 0
    )

    /// Every pair involving `actor` on either side, which is what a
    /// per-selected-actor panel shows.
    func pairs(involving actor: ReferenceKey) -> [DetectionPairReadout] {
        pairs.filter { $0.observer == actor || $0.target == actor }
    }
}

extension PerceptionRuntime {
    /// The pass as a flat value, in pair order.
    func readout() -> PerceptionReadout {
        let names = Dictionary(uniqueKeysWithValues: observers.map { ($0.key, $0.name) })
            .merging(
                Dictionary(uniqueKeysWithValues: targets.map { ($0.key, $0.name) }),
                uniquingKeysWith: { observer, _ in observer }
            )
        let rows = pairs.keys.sorted().compactMap { key -> DetectionPairReadout? in
            guard let pair = pairs[key] else { return nil }
            return DetectionPairReadout(
                observer: key.observer,
                observerName: names[key.observer] ?? key.observer.description,
                target: key.target,
                targetName: names[key.target] ?? key.target.description,
                state: pair.state,
                level: pair.level,
                detectionValue: pair.breakdown.value,
                soundFactor: pair.breakdown.soundFactor,
                visualFactor: pair.breakdown.visualFactor,
                distance: pair.distance,
                hasLineOfSight: pair.hasLineOfSight,
                isInViewCone: pair.isInViewCone,
                lastKnownPosition: pair.lastKnownPosition
            )
        }
        return PerceptionReadout(
            pairs: rows,
            observerCount: observers.count,
            targetCount: targets.count,
            droppedPairCount: droppedPairCount,
            lineOfSightQueryCount: lineOfSightQueryCount,
            stepCount: stepCount
        )
    }
}
