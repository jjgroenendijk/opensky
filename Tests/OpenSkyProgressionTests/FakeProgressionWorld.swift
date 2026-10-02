// Fakes for the perk and progression coordinator suites. Every answer is a
// stored value and every call is recorded.

import OpenSkyActorsInterface
import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionInterface

@MainActor
final class FakeProgressionWorld: PerkWorld, ProgressionWorld {
    var residents: [ReferenceKey: ActorValueHolder] = [:]
    var worn = WornArmorProfile.none
    private(set) var changeCount = 0
    private(set) var reconciled: [ReferenceKey] = []
    private(set) var wornArmorReads: [ReferenceKey] = []

    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        key == .player ? .player : residents[key]
    }

    func actorValue(at _: Int32, on _: ActorValueHolder) -> Float? {
        nil
    }

    func perksChanged(_: PerkRuntime) {
        changeCount += 1
    }

    func reconcileAbilities(on holder: ActorValueHolder, perks _: PerkRuntime) {
        reconciled.append(holder.key)
    }

    func wornArmor(of key: ReferenceKey) -> WornArmorProfile {
        wornArmorReads.append(key)
        return worn
    }

    func conditionContext() -> ConditionContext {
        ConditionContext()
    }

    func conditionText(_ condition: Condition) -> String {
        "function \(condition.functionIndex)"
    }
}
