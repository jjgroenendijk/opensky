import Foundation
import OpenSkyFormatsESM
import OpenSkyPerceptionInterface
import simd

extension PerceptionRuntime {
    /// The pass as a flat value, in pair order.
    public func readout() -> PerceptionReadout {
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
