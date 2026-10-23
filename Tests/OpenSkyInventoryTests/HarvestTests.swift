// Harvesting synthetic flora: the produce grant, the harvested component, the
// refused second harvest, the label change, the season roll, and the cell reset.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
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
    /// A spring morning, three game days in.
    static let moment = HarvestMoment(day: 3, season: .spring)

    static func flora(
        _ reference: FormID, produce: FormID?, chances: [UInt8]? = nil
    ) -> PlacedInteraction {
        PlacedInteraction(
            reference: reference,
            base: floraBase,
            position: .zero,
            name: "Fixture Plant",
            action: .harvest,
            actionLabel: InteractionAction.harvest.defaultLabel,
            sounds: nil,
            produce: HarvestProduce(
                ingredient: produce, harvestSound: nil, seasonalChance: chances
            )
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
        let outcome = try harness.runtime.harvest(target, at: Self.moment)
        #expect(outcome.granted == [InventoryStack(item: Fixture.lockpick, count: 1)])
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 1)
        #expect(harness.runtime.isHarvested(target))
        #expect(harness.runtime.labelled(target).actionLabel == InteractionAction.harvestedLabel)
        #expect(
            harness.store.component(ReferenceHarvestState.self, for: outcome.reference)
                == ReferenceHarvestState(isHarvested: true, harvestedOnDay: 3)
        )
    }

    @Test func aGreenThumbHarvestGrantsTheCountItIsGiven() throws {
        let harness = try Self.harness()
        let target = Self.flora(Self.plant, produce: Fixture.lockpick)
        let outcome = try harness.runtime.harvest(target, at: Self.moment, count: 2)
        #expect(outcome.granted == [InventoryStack(item: Fixture.lockpick, count: 2)])
    }

    @Test func aSecondHarvestIsRefusedAndWritesNothing() throws {
        let harness = try Self.harness()
        let target = Self.flora(Self.plant, produce: Fixture.lockpick)
        try harness.runtime.harvest(target, at: Self.moment)
        #expect(throws: HarvestError.alreadyHarvested(Self.plant)) {
            try harness.runtime.harvest(target, at: Self.moment)
        }
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 1)
    }

    @Test func aLeveledProduceGrantsItsDeterministicPick() throws {
        let harness = try Self.harness()
        let outcome = try harness.runtime.harvest(
            Self.flora(Self.leveledPlant, produce: Fixture.singlePickList), at: Self.moment
        )
        #expect(outcome.granted.count == 1)
        #expect(outcome.granted.first?.item != Fixture.singlePickList)
    }

    @Test func aPlantWithoutProduceWritesNothing() throws {
        let harness = try Self.harness()
        #expect(throws: HarvestError.noProduce(Self.floraBase)) {
            try harness.runtime.harvest(Self.flora(Self.barePlant, produce: nil), at: Self.moment)
        }
        #expect(harness.store.dirtyCount == 0)
    }

    @Test func aResetMakesThePlantHarvestableAgain() throws {
        let harness = try Self.harness()
        let target = Self.flora(Self.plant, produce: Fixture.lockpick)
        try harness.runtime.harvest(target, at: Self.moment)
        try harness.runtime.resetHarvest(target)
        #expect(!harness.runtime.isHarvested(target))
        try harness.runtime.harvest(target, at: Self.moment)
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 2)
    }

    /// PFPC 0 in spring: the plant is picked bare, and still counts as harvested.
    @Test func anOutOfSeasonHarvestYieldsNothingButMarksThePlant() throws {
        let harness = try Self.harness()
        let target = Self.flora(Self.plant, produce: Fixture.lockpick, chances: [0, 100, 100, 100])
        let outcome = try harness.runtime.harvest(target, at: Self.moment)
        #expect(outcome.granted.isEmpty)
        #expect(harness.runtime.isHarvested(target))
        let summer = HarvestMoment(day: 3, season: .summer)
        let other = Self.flora(
            Self.leveledPlant,
            produce: Fixture.lockpick,
            chances: [0, 100, 0, 0]
        )
        #expect(try harness.runtime.harvest(other, at: summer).granted.count == 1)
    }

    /// Six vanilla plants carry PFPC 0 in every season and still yield in the game.
    @Test func allZeroChancesMeanNoSeasonalData() {
        #expect(HarvestSeason.spring.chance(in: [0, 0, 0, 0]) == nil)
        #expect(HarvestSeason.yields(chances: [0, 0, 0, 0], season: .winter, roll: 99))
        #expect(!HarvestSeason.yields(chances: [50, 0, 0, 0], season: .spring, roll: 50))
        #expect(HarvestSeason.yields(chances: [50, 0, 0, 0], season: .spring, roll: 49))
        #expect(HarvestSeason.yields(chances: [50, 0, 0, 0], season: nil, roll: 99))
    }

    /// Tamriel months 1 to 12 start in Morning Star, a winter month.
    @Test func theMonthPicksTheSeason() {
        #expect(HarvestSeason(month: 1) == .winter)
        #expect(HarvestSeason(month: 3) == .spring)
        #expect(HarvestSeason(month: 6) == .summer)
        #expect(HarvestSeason(month: 9) == .fall)
        #expect(HarvestSeason(month: 12) == .winter)
        #expect(HarvestSeason(month: 13) == nil)
    }
}
