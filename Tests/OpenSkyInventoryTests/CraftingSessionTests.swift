// A crafting session at a synthetic station: keyword filtering, verdicts,
// atomic consumption, the created count, and the reported skill use.

import FeaturesTesting
import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct CraftingSessionTests {
    private typealias Fixture = InventoryBaselineFixture

    static let forge: UInt32 = 0x0000_9000
    static let otherBench: UInt32 = 0x0000_9010
    static let swordRecipe = ResolvedFormID(plugin: "Base.esm", objectID: 0x10)
    static let picksRecipe = ResolvedFormID(plugin: "Base.esm", objectID: 0x11)

    final class FakeConditions: RecipeConditionChecking {
        var failing: String?
        var smithing: Float = 15
        var temperingEnchanted: [Bool?] = []

        func failingFunction(
            in _: ConditionList,
            sourcePlugin _: String,
            temperingEnchanted: Bool?
        ) -> String? {
            self.temperingEnchanted.append(temperingEnchanted)
            return failing
        }

        func skillLevel(at _: Int32) -> Float? {
            smithing
        }
    }

    final class FakeSkills: SkillUseReporting {
        var uses: [SkillUseEvent] = []

        func reportSkillUse(_ use: SkillUseEvent) -> Float {
            uses.append(use)
            return use.amount
        }
    }

    struct Harness {
        let inventory: InventoryRuntime
        let session: CraftingSession
        let conditions: FakeConditions
        let skills: FakeSkills
    }

    static func harness(bench: WorkbenchType = .createObject) throws -> Harness {
        let file = try ESMFixture.plugin(records: [
            RecipeFixture.recordBytes(
                formID: 0x10, editorID: "RecipeSword",
                components: [(Fixture.lockpick.rawValue, 2)],
                createdObject: Fixture.sword.rawValue, workbenchKeyword: forge
            ),
            RecipeFixture.recordBytes(
                formID: 0x11, editorID: "RecipePicks",
                components: [(Fixture.sword.rawValue, 1)],
                createdObject: Fixture.lockpick.rawValue, workbenchKeyword: forge,
                createdCount: 3
            ),
            RecipeFixture.recordBytes(
                formID: 0x12, editorID: "RecipeElsewhere",
                createdObject: Fixture.sword.rawValue, workbenchKeyword: otherBench
            )
        ])
        let catalog = CraftingCatalog(
            recipes: RecipeStore(plugins: [("Base.esm", file)]),
            itemPlugin: FormIDResolver(pluginName: "Base.esm", masters: []),
            stations: []
        )
        let inventory = try InventoryRuntime(
            store: WorldStateStore(),
            baselines: Fixture.resolver()
        )
        let station = PlacedInteraction(
            reference: FormID(0x8000), base: FormID(0x8001), position: .zero, name: "Forge",
            action: .use, actionLabel: "Activate", sounds: nil,
            station: CraftingStation(
                workbench: Workbench(benchType: bench, skillIndex: 10),
                keywords: [FormID(forge)]
            )
        )
        let conditions = FakeConditions()
        let skills = FakeSkills()
        let session = try CraftingSession(
            event: #require(CraftingActivationEvent(interaction: station)),
            catalog: catalog,
            inventory: inventory,
            conditions: conditions,
            skills: skills
        )
        return Harness(
            inventory: inventory,
            session: session,
            conditions: conditions,
            skills: skills
        )
    }

    @Test func aStationActivationIsOnlyRaisedForAWorkbench() {
        let plain = PlacedInteraction(
            reference: FormID(1), base: FormID(2), position: .zero, name: "Chair",
            action: .use, actionLabel: "Activate", sounds: nil
        )
        #expect(CraftingActivationEvent(interaction: plain) == nil)
    }

    @Test func theSessionListsTheStationKeywordRecipes() throws {
        let harness = try Self.harness()
        #expect(harness.session.recipes.map(\.id) == [Self.swordRecipe, Self.picksRecipe])
        #expect(harness.session.station.skill == ActorValueIdentity.index(named: "Smithing"))
    }

    @Test func verdictsNameMissingPartsAndFailingConditions() throws {
        let harness = try Self.harness()
        let sword = try #require(harness.session.statuses.first)
        #expect(sword.eligibility.shortfalls == [
            ComponentShortfall(item: Fixture.lockpick, required: 2, held: 0)
        ])
        try harness.inventory.add(Fixture.lockpick, count: 2, to: .player)
        #expect(harness.session.statuses.first?.eligibility.isEligible == true)
        harness.conditions.failing = "HasPerk"
        #expect(harness.session.statuses.first?.eligibility.failingFunction == "HasPerk")
    }

    @Test func aCraftConsumesThePartsAndReportsTheSkill() throws {
        let harness = try Self.harness()
        try harness.inventory.add(Fixture.lockpick, count: 5, to: .player)
        let outcome = try harness.session.craft(Self.swordRecipe)
        #expect(outcome.consumed == [InventoryStack(item: Fixture.lockpick, count: 2)])
        #expect(harness.inventory.count(of: Fixture.lockpick, in: .player) == 3)
        #expect(harness.inventory.count(of: Fixture.sword, in: .player) == 1)
        let use = try #require(harness.skills.uses.first)
        #expect(try use
            .action == .craft(skill: #require(ActorValueIdentity.index(named: "Smithing"))))
        #expect(use.actor == .player)
    }

    @Test func theCreatedCountIsHonored() throws {
        let harness = try Self.harness()
        try harness.inventory.add(Fixture.sword, count: 1, to: .player)
        try harness.session.craft(Self.picksRecipe)
        #expect(harness.inventory.count(of: Fixture.lockpick, in: .player) == 3)
        #expect(harness.inventory.count(of: Fixture.sword, in: .player) == 0)
    }

    @Test func aFailedPreconditionChangesNothing() throws {
        let harness = try Self.harness()
        try harness.inventory.add(Fixture.lockpick, count: 1, to: .player)
        let before = harness.inventory.inventory(of: .player)
        #expect(throws: CraftingError.self) { try harness.session.craft(Self.swordRecipe) }
        harness.conditions.failing = "HasPerk"
        try harness.inventory.add(Fixture.lockpick, count: 1, to: .player)
        let ready = harness.inventory.inventory(of: .player)
        #expect(throws: CraftingError.self) { try harness.session.craft(Self.swordRecipe) }
        #expect(harness.inventory.inventory(of: .player) == ready)
        #expect(before.count(of: Fixture.lockpick) == 1)
        #expect(harness.skills.uses.isEmpty)
    }
}
