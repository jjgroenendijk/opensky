// A damage effect with no duration and a taper, as Firebolt's fire damage: the hit takes
// the whole magnitude at once, and the taper burns on (docs/engine/magic.md#tapering).

import Foundation
@testable import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyWorldConditions
@testable import OpenSkyWorldState
import Testing

@MainActor
struct TaperedDamageTests {
    private static let burn: UInt32 = 0x60

    private func runtime() throws -> ActiveEffectRuntime {
        let record = ActiveEffectFixture.magicEffect(
            formID: Self.burn, editorID: "FireDamageBurn", name: "Fire Damage",
            data: ActiveEffectFixture.data(
                flags: [.detrimental], archetype: 0, primaryValue: 24,
                taperWeight: 0.3, taperCurve: 2, taperDuration: 1
            )
        )
        let store = WorldStateStore()
        let values = ActorValueRuntime(store: store, baselines: ActorValueBaselineFixture.flat())
        let file = try ActiveEffectFixture.plugin(records: [record])
        return ActiveEffectRuntime(
            values: values,
            effects: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)]),
            conditions: ConditionContext(functions: .standard)
        )
    }

    @Test func theHitTakesTheMagnitudeAndTheTaperBurnsOn() throws {
        var runtime = try runtime()
        let stored = ActiveEffectFixture.apply(
            &runtime, [ActiveEffectFixture.entry(Self.burn, magnitude: 25)]
        )
        #expect(runtime.values.current(of: .player).health == 75)
        #expect(stored.count == 1)
        let steps = Int((2 / ActiveEffectRuntime.fixedStepSeconds).rounded())
        for _ in 0 ..< steps {
            runtime.step(over: [.player])
        }
        // UESP's total for the burn: 25 * 0.3 * 1 / (2 + 1).
        #expect(abs(runtime.values.current(of: .player).health - 72.5) < 0.01)
    }
}
