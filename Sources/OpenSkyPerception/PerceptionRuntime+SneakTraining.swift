// Sneak trains while a crouched target stays hidden near an observer. UESP
// "Skyrim:Leveling". See docs/engine/detection.md.

import OpenSkyFormatsESM
import OpenSkyPerceptionInterface
import OpenSkyPhysics

extension PerceptionRuntime {
    /// Crouched targets that an observer within `skillUseRange` tracks and that
    /// no observer detects, in roster order.
    public func hiddenSneakers() -> [ReferenceKey] {
        let range = settings.skillUseRange.value
        return targets.filter(\.isSneaking).map(\.key).filter { target in
            let watched = pairs.filter { $0.key.target == target }
            return watched.contains { $0.value.distance <= range }
                && !watched.contains { $0.value.state == .detected }
        }
    }
}
