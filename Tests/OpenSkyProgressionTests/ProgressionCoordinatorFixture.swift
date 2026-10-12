// A progression coordinator wired over the perk fixture tree, with every actor
// value fixed at one level.

import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyGameData
@testable import OpenSkyProgression
@testable import OpenSkyWorldState

@MainActor
enum ProgressionCoordinatorFixture {
    /// The caller holds `world`, because the coordinators keep it weakly.
    static func make(
        world: FakeProgressionWorld, skillLevel: Float = 15
    ) throws -> ProgressionCoordinator {
        let store = WorldStateStore()
        let index = try PerkRuntimeFixture.index()
        let information = PerkRuntimeFixture.informationStore(index: index)
        let perkStore = PerkRuntimeFixture.perkStore(index: index)
        let perks = PerkCoordinator()
        perks.attach(world: world)
        perks.wire(
            PerkRuntime(store: store, perks: perkStore, conditionRegistry: .empty),
            baselines: nil,
            pluginName: PerkRuntimeFixture.pluginName
        )
        let coordinator = ProgressionCoordinator(perks: perks)
        coordinator.attach(world: world)
        let values = FixedActorValues(store: store, indexedValue: skillLevel)
        coordinator.wireSkills(values: values, information: information)
        coordinator.wireLeveling(values: values, perkStore: perkStore, information: information)
        return coordinator
    }
}
