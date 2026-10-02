// Harvesting synthetic flora: the produce grant, the harvested component, the
// refused second harvest, the label change, and the reset.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import OpenSkyInventoryTesting
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct HarvestTests {
    private typealias Fixture = InventoryBaselineFixture
    private typealias Items = WorldItemRuntimeTests

    static let plant = FormID(0x0000_0800)
    static let leveledPlant = FormID(0x0000_0810)
    static let barePlant = FormID(0x0000_0820)
    static let floraBase = FormID(0x0000_5000)

    static func flora(_ reference: FormID, produce: FormID?) -> PlacedInteraction {
        PlacedInteraction(
            reference: reference,
            base: floraBase,
            position: .zero,
            name: "Fixture Plant",
            action: .harvest,
            actionLabel: InteractionAction.harvest.defaultLabel,
            sounds: nil,
            produce: HarvestProduce(ingredient: produce, harvestSound: nil, seasonalChance: nil)
        )
    }

    static func harness() throws -> WorldItemRuntimeTests.Harness {
        try Items.harness(entries: [
            Items.entry(formID: plant, base: floraBase),
            Items.entry(formID: leveledPlant, base: floraBase),
            Items.entry(formID: barePlant, base: floraBase)
        ])
    }

    @Test func aHarvestGrantsOneProduceAndMarksThePlant() throws {
        let harness = try Self.harness()
        let target = Self.flora(Self.plant, produce: Fixture.lockpick)
        #expect(harness.runtime.labelled(target).actionLabel == "Harvest")
        let outcome = try harness.runtime.harvest(target)
        #expect(outcome.granted == [InventoryStack(item: Fixture.lockpick, count: 1)])
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 1)
        #expect(harness.runtime.isHarvested(target))
        #expect(harness.runtime.labelled(target).actionLabel == InteractionAction.harvestedLabel)
        #expect(
            harness.store.component(ReferenceHarvestState.self, for: outcome.reference)
                == .harvested
        )
    }

    @Test func aSecondHarvestIsRefusedAndWritesNothing() throws {
        let harness = try Self.harness()
        let target = Self.flora(Self.plant, produce: Fixture.lockpick)
        try harness.runtime.harvest(target)
        #expect(throws: HarvestError.alreadyHarvested(Self.plant)) {
            try harness.runtime.harvest(target)
        }
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 1)
    }

    @Test func aLeveledProduceGrantsItsDeterministicPick() throws {
        let harness = try Self.harness()
        let outcome = try harness.runtime.harvest(
            Self.flora(Self.leveledPlant, produce: Fixture.singlePickList)
        )
        #expect(outcome.granted.count == 1)
        #expect(outcome.granted.first?.item != Fixture.singlePickList)
    }

    @Test func aPlantWithoutProduceWritesNothing() throws {
        let harness = try Self.harness()
        #expect(throws: HarvestError.noProduce(Self.floraBase)) {
            try harness.runtime.harvest(Self.flora(Self.barePlant, produce: nil))
        }
        #expect(harness.store.dirtyCount == 0)
    }

    @Test func aResetMakesThePlantHarvestableAgain() throws {
        let harness = try Self.harness()
        let target = Self.flora(Self.plant, produce: Fixture.lockpick)
        try harness.runtime.harvest(target)
        try harness.runtime.resetHarvest(target)
        #expect(!harness.runtime.isHarvested(target))
        try harness.runtime.harvest(target)
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 2)
    }
}
