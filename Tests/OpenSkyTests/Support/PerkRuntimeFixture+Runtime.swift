// The perk runtime, its tree index, and the actor values the perk suites
// spend. Needs Progression, Actors, and the whole-game condition registry.

@testable import OpenSkyActors
import OpenSkyActorsTesting
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionTesting
@testable import OpenSkyWorld
@testable import OpenSkyWorldState

extension PerkRuntimeFixture {
    /// Where each fixture perk sits in the fixture tree.
    public static func trees(index: RecordIndex) -> PerkTreeIndex {
        PerkTreeIndex(
            information: informationStore(index: index),
            perks: perkStore(index: index)
        )
    }

    /// A perk runtime over a fresh world-state store, plus the store so a suite
    /// can snapshot it.
    ///
    /// The store argument is optional rather than defaulted because a
    /// main-actor default value cannot be written in a nonisolated context.
    public static func runtime(
        store: WorldStateStore? = nil
    ) throws -> (PerkRuntime, WorldStateStore) {
        let worldState = store ?? WorldStateStore()
        return try (
            PerkRuntime(
                store: worldState,
                perks: perkStore(index: index()),
                conditionRegistry: .standard
            ),
            worldState
        )
    }

    /// An actor-value runtime whose subjects start at 100 of everything and
    /// regenerate nothing, matching `SpellbookFixture.values`.
    public static func values(store: WorldStateStore) -> ActorValueRuntime {
        ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineFixture.flat()
        )
    }
}
