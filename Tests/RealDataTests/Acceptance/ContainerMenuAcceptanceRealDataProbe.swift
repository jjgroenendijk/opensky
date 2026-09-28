// The probe world and the movie-free half of the M12.2.3 acceptance gate
// (issue #179). Satellite of ContainerMenuAcceptanceRealDataTests.swift, which
// drives the two vanilla movies; split so both stay inside the strict-lint
// type-length cap.

import Foundation
@testable import opensky
import Testing

extension ContainerMenuAcceptanceRealDataTests {
    @MainActor
    struct ProbeShop {
        let inventory: InventoryRuntime
        let container: InventoryHolder
        let session: BarterSession
        let model: ContainerMenuModel
        let pricing: BarterPricing

        func totals() -> [FormID: Int32] {
            var totals: [FormID: Int32] = [:]
            for holder in [container, InventoryHolder.player] {
                for stack in inventory.inventory(of: holder).stacks {
                    totals[stack.item, default: 0] += stack.count
                }
            }
            return totals
        }

        func rebuild(mode: ContainerMenuModel.Mode) -> ContainerMenuModel {
            ContainerMenuModel.build(
                container: container,
                containerName: model.containerName,
                mode: mode,
                pricing: pricing,
                runtime: inventory
            )
        }
    }

    /// A player and a merchant both stocked from the install's own item index,
    /// priced by the install's own `fBarterMin` and `fBarterMax`. Nothing is
    /// written to the install; both inventories live in an in-memory store.
    @MainActor
    func makeShop(root: GameDataRoot, mode: ContainerMenuModel.Mode) throws -> ProbeShop {
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let baselines = InventoryBaselineResolver.build(from: file)
        let inventory = InventoryRuntime(store: WorldStateStore(), baselines: baselines)
        let items = WorldItemRuntime(inventory: inventory)
        let container = InventoryHolder(
            key: inventory.store.allocateGeneratedKey(), owner: .generated, cell: nil
        )
        for family in ItemDefinition.Family.allCases {
            for definition in baselines.items.definitions(of: family).prefix(3) {
                _ = try? inventory.add(definition.formID, count: 2, to: .player)
                _ = try? inventory.add(definition.formID, count: 2, to: container)
            }
        }
        try inventory.add(InventoryRuntime.vanillaGoldFormID, count: 5000, to: .player)
        try inventory.add(InventoryRuntime.vanillaGoldFormID, count: 800, to: container)
        let pricing = BarterPricing.resolve(
            store: GameSettingLoader.load(root: root, baseFile: file)
        )
        #expect(pricing.source.contains("Skyrim.esm"), "barter GMSTs did not come from the plugin")
        return ProbeShop(
            inventory: inventory,
            container: container,
            session: BarterSession(runtime: items, merchant: container, pricing: pricing),
            model: ContainerMenuModel.build(
                container: container,
                containerName: "Probe merchant",
                mode: mode,
                pricing: pricing,
                runtime: inventory
            ),
            pricing: pricing
        )
    }

    /// The two-pane list and the pricing must work with no install and no movie
    /// at all, so the milestone surface never depends on the movie coming up.
    @Test @MainActor
    func theTwoPaneListIsIndependentOfTheMovie() throws {
        let baselines = try InventoryBaselineFixture.resolver()
        let inventory = InventoryRuntime(store: WorldStateStore(), baselines: baselines)
        let container = InventoryHolder(
            key: inventory.store.allocateGeneratedKey(), owner: .generated, cell: nil
        )
        try inventory.add(InventoryBaselineFixture.sword, count: 1, to: container)
        let model = ContainerMenuModel.build(
            container: container, containerName: "Chest", mode: .barter,
            pricing: .vanilla, runtime: inventory
        )
        #expect(model.selectedEntry?.name == "IronSword")
        #expect(try model.price(for: #require(model.selectedEntry)) == 78)
    }
}
