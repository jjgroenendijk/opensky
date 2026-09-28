import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyPerceptionInterface
import simd

extension PerceptionRuntime {
    /// This pass as a condition seam: every tracked pair plus every roster
    /// member's position.
    public func resolution() -> DetectionResolution {
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
