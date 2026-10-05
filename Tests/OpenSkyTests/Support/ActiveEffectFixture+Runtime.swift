// The effect runtime setup that the active-effect suites share.

import FeaturesTesting
@testable import OpenSkyActors
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
@testable import OpenSkyWorldState

extension ActiveEffectFixture {
    /// A runtime over `effectRecords` and a fresh store. Every actor value has
    /// a maximum of 100 and does not regenerate.
    public static func runtime(
        conditionRegistry: ConditionFunctionRegistry
    ) throws -> (ActiveEffectRuntime, WorldStateStore) {
        let store = WorldStateStore()
        let values = ActorValueRuntime(store: store, baselines: ActorValueBaselineFixture.flat())
        let file = try plugin(records: effectRecords)
        let effects = MagicEffectStore(plugins: [(pluginName, file)])
        return (
            ActiveEffectRuntime(
                values: values, effects: effects, conditionRegistry: conditionRegistry
            ),
            store
        )
    }

    public static func entry(
        _ formID: UInt32,
        magnitude: Float,
        duration: UInt32 = 0,
        conditions: ConditionList = ConditionList()
    ) -> MagicItemEffect {
        MagicItemEffect(
            effect: FormID(formID),
            magnitude: magnitude,
            area: 0,
            duration: duration,
            conditions: conditions
        )
    }

    /// The potion every applied entry comes from.
    public static var potionSource: ActiveEffectSource {
        ActiveEffectSource(
            kind: .potion,
            record: .plugin(name: pluginName.lowercased(), objectID: 0x500)
        )
    }

    /// Applies `entries` to the player from `potionSource`.
    @discardableResult
    public static func apply(
        _ runtime: inout ActiveEffectRuntime,
        _ entries: [MagicItemEffect]
    ) -> [ActiveEffect] {
        runtime.apply(entries, fromPlugin: pluginName, source: potionSource, on: .player)
    }
}
