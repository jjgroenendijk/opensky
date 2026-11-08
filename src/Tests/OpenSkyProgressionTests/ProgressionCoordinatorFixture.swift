// A progression coordinator wired over the perk fixture tree, with every actor
// value fixed at one level.

import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyGameData
@testable import OpenSkyProgression
@testable import OpenSkyWorldState

@MainActor
enum ProgressionCoordinatorFixture {
    static func make(
        world: FakeProgressionWorld,
        skillLevel: Float = 15,
        storyEvents: (any StoryEventReporting)? = nil,
        texts: ProgressionTexts = .vanilla
    ) throws -> ProgressionCoordinator {
        let store = WorldStateStore()
        let index = try PerkRuntimeFixture.index()
        let information = PerkRuntimeFixture.informationStore(index: index)
        let perkStore = PerkRuntimeFixture.perkStore(index: index)
        let perks = PerkCoordinator(
            world: world,
            runtime: PerkRuntime(store: store, perks: perkStore, conditionRegistry: .empty),
            baselines: nil,
            pluginName: PerkRuntimeFixture.pluginName
        )
        return ProgressionCoordinator(
            perks: perks,
            world: world,
            data: ProgressionSessionData(
                values: FixedActorValues(store: store, indexedValue: skillLevel),
                information: information,
                perkStore: perkStore,
                texts: texts
            ),
            storyEvents: storyEvents
        )
    }
}
