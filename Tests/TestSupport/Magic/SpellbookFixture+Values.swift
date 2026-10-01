// The actor values the caster suites spend from. Needs the Actors runtime, so
// it lives beside the suites that combine it with Magic.

@testable import OpenSkyActors
import OpenSkyActorsTesting
import OpenSkyMagicTesting
@testable import OpenSkyWorldState

extension SpellbookFixture {
    /// An actor-value runtime whose subjects all start at 100 of everything and
    /// regenerate nothing, so a magicka number in a suite is only ever what a
    /// cast spent.
    public static func values(store: WorldStateStore) -> ActorValueRuntime {
        ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineFixture.flat()
        )
    }
}
