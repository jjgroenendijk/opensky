// Harvesting synthetic flora: the produce grant, the harvested component, the
// refused second harvest, the label change, the reset, and the regrowth.

import FeaturesTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
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
    /// Game days passed at the harvest in these tests.
    static let day: Float = 3

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
        #expect(harness.runtime.labelled(target, onDay: Self.day).actionLabel == "Harvest")
        let outcome = try harness.runtime.harvest(target, onDay: Self.day)
        #expect(outcome.granted == [InventoryStack(item: Fixture.lockpick, count: 1)])
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 1)
        #expect(harness.runtime.isHarvested(target, onDay: Self.day))
        #expect(
            harness.runtime.labelled(target, onDay: Self.day).actionLabel
                == InteractionAction.harvestedLabel
        )
        #expect(
            harness.store.component(ReferenceHarvestState.self, for: outcome.reference)
                == ReferenceHarvestState(isHarvested: true, harvestedOnDay: Self.day)
        )
    }

    @Test func aSecondHarvestIsRefusedAndWritesNothing() throws {
        let harness = try Self.harness()
        let target = Self.flora(Self.plant, produce: Fixture.lockpick)
        try harness.runtime.harvest(target, onDay: Self.day)
        #expect(throws: HarvestError.alreadyHarvested(Self.plant)) {
            try harness.runtime.harvest(target, onDay: Self.day)
        }
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 1)
    }

    @Test func aLeveledProduceGrantsItsDeterministicPick() throws {
        let harness = try Self.harness()
        let outcome = try harness.runtime.harvest(
            Self.flora(Self.leveledPlant, produce: Fixture.singlePickList),
            onDay: Self.day
        )
        #expect(outcome.granted.count == 1)
        #expect(outcome.granted.first?.item != Fixture.singlePickList)
    }

    @Test func aPlantWithoutProduceWritesNothing() throws {
        let harness = try Self.harness()
        #expect(throws: HarvestError.noProduce(Self.floraBase)) {
            try harness.runtime.harvest(Self.flora(Self.barePlant, produce: nil), onDay: Self.day)
        }
        #expect(harness.store.dirtyCount == 0)
    }

    @Test func aResetMakesThePlantHarvestableAgain() throws {
        let harness = try Self.harness()
        let target = Self.flora(Self.plant, produce: Fixture.lockpick)
        try harness.runtime.harvest(target, onDay: Self.day)
        try harness.runtime.resetHarvest(target)
        #expect(!harness.runtime.isHarvested(target, onDay: Self.day))
        try harness.runtime.harvest(target, onDay: Self.day)
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 2)
    }

    /// `iHoursToRespawnCell` is 240 hours, so the plant regrows 10 game days on.
    @Test func aPlantGrowsBackWhenItsCellResets() throws {
        let harness = try Self.harness()
        let target = Self.flora(Self.plant, produce: Fixture.lockpick)
        try harness.runtime.harvest(target, onDay: Self.day)
        #expect(harness.runtime.regrowthDay(of: target) == Self.day + 10)

        #expect(harness.runtime.isHarvested(target, onDay: Self.day + 9.9))
        #expect(!harness.runtime.isHarvested(target, onDay: Self.day + 10))
        #expect(harness.runtime.labelled(target, onDay: Self.day + 10).actionLabel == "Harvest")
        try harness.runtime.harvest(target, onDay: Self.day + 10)
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 2)
    }

    /// A harvest without a known day, as in an older save, never regrows alone.
    @Test func aHarvestWithoutADayStaysHarvested() {
        let regrowth = HarvestRegrowth.vanilla
        #expect(regrowth.isHarvested(.harvested, onDay: 1000))
        #expect(regrowth.regrowthDay(of: .harvested) == nil)
        #expect(!regrowth.isHarvested(nil, onDay: 1000))
    }

    @Test func theIntervalComesFromTheLoadOrderAndRefusesNonsense() {
        let timed = ReferenceHarvestState(isHarvested: true, harvestedOnDay: 0)
        #expect(HarvestRegrowth(hours: 48).regrowthDay(of: timed) == 2)
        #expect(HarvestRegrowth(hours: 0).hours == HarvestRegrowth.vanillaHours)
        #expect(HarvestRegrowth(hours: .nan).hours == HarvestRegrowth.vanillaHours)
        // Without a clock, a harvested plant stays harvested.
        #expect(HarvestRegrowth.vanilla.isHarvested(timed, onDay: nil))
    }
}
