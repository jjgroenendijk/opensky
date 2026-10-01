import OpenSkyPerceptionInterface
import OpenSkyPhysics
import simd

extension DetectionPairState {
    /// One step of accumulation or decay. `targetPosition` becomes the investigate
    /// position whenever anything is perceived. Zero or non-finite `seconds`
    /// leaves the state alone.
    public func advanced(
        inputs: DetectionInputs,
        targetPosition: SIMD3<Float>,
        by seconds: Float,
        settings: DetectionSettings
    ) -> DetectionPairState {
        let breakdown = DetectionFormula.breakdown(inputs: inputs, settings: settings)
        var updated = self
        updated.breakdown = breakdown
        updated.distance = inputs.distance
        updated.hasLineOfSight = inputs.hasLineOfSight
        updated.isInViewCone = inputs.isInViewCone
        guard seconds.isFinite, seconds > 0 else { return updated }

        let ceiling = max(0, settings.detectedLevel.value)
        if breakdown.isPerceiving {
            let full = max(Float.leastNormalMagnitude, settings.fullDetectionValue.value)
            let rate = min(1, breakdown.value / full) * max(0, settings.gainPerSecond.value)
            updated.level = min(ceiling, level + rate * seconds)
            updated.lastKnownPosition = targetPosition
        } else {
            updated.level = max(0, level - max(0, settings.decayPerSecond.value) * seconds)
            if updated.level <= 0 {
                updated.lastKnownPosition = nil
            }
        }
        updated.state = Self.classify(level: updated.level, settings: settings)
        return updated
    }

    /// The state a level reads as. `detected` needs the full level, so an
    /// observer is only ever certain at the top of the scale.
    public static func classify(level: Float, settings: DetectionSettings) -> DetectionState {
        if level >= max(0, settings.detectedLevel.value) {
            return .detected
        }
        return level >= max(0, settings.suspiciousLevel.value) ? .suspicious : .unaware
    }
}
