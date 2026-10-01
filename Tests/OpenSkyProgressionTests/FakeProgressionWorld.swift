// Fakes for the perk and progression coordinator suites. Every answer is a
// stored value and every call is recorded.

import OpenSkyActorsInterface
import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionInterface
@testable import OpenSkyWorldState

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

/// Every value reads 15 and no write changes one. The leveling state lives in
/// `store`, which is all the perk-point tests read.
@MainActor
struct FixedActorValues: ActorValueAccess {
    let store: WorldStateStore
    let baselines = ActorValueBaselineResolver(
        fallback: ActorValueBaseline(
            maximums: ActorValues(repeating: 100),
            regenPercentPerSecond: .zero
        )
    )

    func baseline(of _: ActorValueHolder) -> ActorValueBaseline {
        baselines.fallback
    }

    func maximums(of _: ActorValueHolder) -> ActorValues {
        ActorValues(repeating: 100)
    }

    func current(of _: ActorValueHolder) -> ActorValues {
        ActorValues(repeating: 100)
    }

    func fractions(of _: ActorValueHolder) -> ActorValues {
        ActorValues(repeating: 1)
    }

    func hasZeroHealth(_: ActorValueHolder) -> Bool {
        false
    }

    func damage(_: ActorValueKind, by _: Float, on _: ActorValueHolder) -> ActorValueState {
        ActorValueState(current: current(of: .player))
    }

    func set(_: ActorValueKind, to _: Float, on _: ActorValueHolder) -> ActorValueState {
        ActorValueState(current: current(of: .player))
    }

    func restoreAll(on _: ActorValueHolder) -> ActorValueState {
        ActorValueState(current: current(of: .player))
    }

    func value(at _: Int32, on _: ActorValueHolder) -> Float? {
        15
    }

    func baseValue(at _: Int32, on _: ActorValueHolder) -> Float? {
        15
    }

    func entry(at _: Int32, on _: ActorValueHolder) -> ActorValueEntry? {
        nil
    }

    func resolvedEntries(of _: ActorValueHolder) -> [Int32: ActorValueEntry] {
        [:]
    }

    func damage(at _: Int32, by _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func restore(at _: Int32, by _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func setValue(at _: Int32, to _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func setBase(at _: Int32, to _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func incrementBase(at _: Int32, by _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func advanceSkill(at _: Int32, by _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func addModifier(
        _: Float,
        to _: ActorValueModifier,
        at _: Int32,
        on _: ActorValueHolder
    ) -> Bool {
        false
    }

    func setModifier(
        _: Float,
        for _: ActorValueModifier,
        at _: Int32,
        on _: ActorValueHolder
    ) -> Bool {
        false
    }

    func forceValue(at _: Int32, to _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func magicDamageMultiplier(
        element _: Int32?,
        on _: ActorValueHolder,
        settings _: ActorResistanceSettings
    ) -> Float {
        1
    }
}
