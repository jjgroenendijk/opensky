// The controller-side magic tick (`GameViewController.advanceMagicEffects`).
//
// `ActiveEffectRuntimeTests` covers what a step does to an effect; this suite
// covers the bridge that drives it, which the engine suites never touch because
// the accumulator and the runtime live on the controller rather than in the
// runtime.
//
// The regression it pins is an exclusivity trap, not a wrong number: `runtime`
// and `accumulator` are two fields of the one `magicEffects` stored property,
// so calling the `mutating` `advance` through `magicEffects.runtime` while
// passing `&magicEffects.accumulator` opened two overlapping exclusive accesses
// to that property and aborted the process on the first simulated frame after
// game data loaded. A regression therefore takes the whole test bundle down
// with "Fatal access conflict detected" rather than failing one expectation.
//
// Records are synthetic and built in code (`ActiveEffectFixture`) — never
// extracted game files (AGENTS.md "Legal & IP boundary").

import AppKit
import Foundation
@testable import OpenSky
@testable import OpenSkyEngine
@testable import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
struct GameViewControllerMagicTickTests {
    /// A controller whose magic runtime is wired over synthetic MGEF records,
    /// which is the state `wireMagicEffects` reaches once a plugin is loaded.
    private func controller() throws -> GameViewController {
        let baselines = ActorValueBaselineResolver(
            fallback: ActorValueBaseline(
                maximums: ActorValues(repeating: 100),
                regenPercentPerSecond: .zero
            )
        )
        let values = ActorValueRuntime(store: WorldStateStore(), baselines: baselines)
        let file = try ActiveEffectFixture.plugin(records: ActiveEffectFixture.effectRecords)
        let effects = MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)])
        let controller = GameViewController()
        controller.magicEffects.runtime = ActiveEffectRuntime(values: values, effects: effects)
        return controller
    }

    @Test func tickingAWiredRuntimeCarriesTheRemainderInTheAccumulator() throws {
        let controller = try controller()
        // Well under the 1/60 s fixed step, so no whole step runs and the whole
        // delta has to survive in the accumulator. A tick that mutated a
        // throwaway copy instead of writing back would leave this at zero.
        controller.advanceMagicEffects(delta: 0.004)
        #expect(controller.magicEffects.accumulator > 0.003)
        #expect(controller.magicEffects.accumulator < 0.005)
    }

    @Test func tickingPastTheFixedStepConsumesAWholeStep() throws {
        let controller = try controller()
        controller.advanceMagicEffects(delta: 0.004)
        // 0.004 + 0.02 clears one 1/60 s step, which the runtime subtracts.
        controller.advanceMagicEffects(delta: 0.02)
        #expect(controller.magicEffects.accumulator < ActiveEffectRuntime.fixedStepSeconds)
        #expect(controller.magicEffects.accumulator > 0)
    }

    @Test func tickingWithoutARuntimeDoesNothing() {
        let controller = GameViewController()
        controller.advanceMagicEffects(delta: 0.004)
        #expect(controller.magicEffects.accumulator == 0)
    }
}
