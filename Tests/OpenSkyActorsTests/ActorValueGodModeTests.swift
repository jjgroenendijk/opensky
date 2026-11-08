// `Debug.SetGodMode` through the actor-value runtime.

@testable import OpenSkyActors
import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
struct ActorValueGodModeTests {
    /// A copy of the runtime shares its store, so god mode set on the copy reads back here.
    @Test func setGodModeWritesThroughACopy() {
        let runtime = ActorValueRuntime(
            store: WorldStateStore(),
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(maximums: .zero, regenPercentPerSecond: .zero)
            ),
            regeneration: .vanilla
        )
        let copy = runtime
        copy.setGodMode(true)
        #expect(runtime.godMode)
        copy.setGodMode(false)
        #expect(!runtime.godMode)
    }
}
