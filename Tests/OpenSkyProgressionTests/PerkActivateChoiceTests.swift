// The Activate entry point through the perk runtime: an owned perk's add-activate-choice
// effects come back with their perk, so a press can run the perk's fragment.

import OpenSkyConditions
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PerkActivateChoiceTests {
    private let target = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x14)

    private func coordinator() throws -> PerkCoordinator {
        let coordinator = PerkCoordinator(world: FakeProgressionWorld())
        try coordinator.wire(
            PerkRuntime(
                store: WorldStateStore(),
                perks: PerkActivateFixture.store(),
                conditionRegistry: .empty
            ),
            baselines: nil,
            pluginName: PerkActivateFixture.pluginName
        )
        return coordinator
    }

    private func choices(_ coordinator: PerkCoordinator) -> [PerkEntryPointChoice] {
        coordinator.choices(
            at: .activate,
            on: .player,
            subjects: { PerkEvaluationSubjects(owner: $0, target: target) }
        )
    }

    private func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: PerkActivateFixture.pluginName.lowercased(), objectID: objectID)
    }

    @Test func anUnownedPerkOffersNoChoice() throws {
        #expect(try choices(coordinator()).isEmpty)
    }

    @Test func anOwnedPerkOffersItsChoicesWithTheirFragments() throws {
        let coordinator = try coordinator()
        coordinator.add(key(PerkActivateFixture.feed), to: .player)

        let activations = choices(coordinator).compactMap(\.activation)
        #expect(activations.map(\.label) == [.inline("Feed"), .inline("Feed in bed")])
        #expect(activations.map(\.fragment?.functionName) == ["Fragment_15", "Fragment_0"])
        #expect(activations.allSatisfy { $0.perkKey == key(PerkActivateFixture.feed) })
    }

    @Test func aRunNowChoiceCarriesItsSpellAndFlags() throws {
        let coordinator = try coordinator()
        coordinator.add(key(PerkActivateFixture.beastFeed), to: .player)

        let choice = try #require(choices(coordinator).first)
        #expect(choice.activation?.runsImmediately == true)
        #expect(choice.activation?.replacesDefault == true)
        #expect(choice.spell?.editorID == "BeastFeedSpell")
        let plan = PerkActivationPlan(choices: [choice])
        #expect(plan.immediate.count == 1)
        #expect(!plan.keepsDefault)
    }

    @Test func activateIsAnEntryPointTheEngineReads() {
        #expect(PerkEntryPoint.engineRead.contains(.activate))
        #expect(PerkEntryPoint.activate.name == "Activate")
    }
}
