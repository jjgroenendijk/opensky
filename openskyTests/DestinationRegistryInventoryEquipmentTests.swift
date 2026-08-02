// Satellite of DestinationRegistryTests (issue #180): the
// World > Inventory & Equipment destination's slice of the registry contract.
// Split out because the parent file sits at the length limit.

import AppKit
@testable import opensky
import Testing

struct DestinationRegistryInventoryEquipmentTests {
    /// The destination is placed under World, directly after the two menu
    /// destinations whose surfaces the gate's loop also drives, and carries its
    /// own SF Symbol.
    @Test @MainActor
    func descriptorPlacementIsPinned() throws {
        let descriptor = try #require(
            DestinationRegistry.destination(id: "inventoryEquipment")
        )
        #expect(descriptor.title == "Inventory & Equipment")
        #expect(descriptor.section == .world)
        #expect(descriptor.symbolName == "backpack")
        #expect(descriptor.sidebarIdentifier == "Destination-inventoryEquipment")
        #expect(descriptor.showsGameView)
        #expect(descriptor.isWorldInspector)

        let ids = DestinationRegistry.all.map(\.id)
        let index = try #require(ids.firstIndex(of: "inventoryEquipment"))
        #expect(ids[index - 1] == "containerMenu")
    }

    /// The factory wires all three sections from one provider value, and hands
    /// the panel the refocus action the registry supplies rather than a seam of
    /// its own.
    @Test @MainActor
    func factoryWiresEverySectionAndRefocus() throws {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)
        guard
            case let .worldInspector(makePanel) = try #require(
                DestinationRegistry.destination(id: "inventoryEquipment")?.content
            )
        else {
            Issue.record("inventoryEquipment is not a world inspector")
            return
        }
        let panel = try #require(makePanel(context) as? InventoryEquipmentPanelViewController)
        panel.loadViewIfNeeded()

        #expect(panel.grantsSection.provider === providers)
        #expect(panel.ownershipSection.provider === providers)
        #expect(panel.equipmentSection.provider === providers)

        panel.equipmentSection.refocusAction?()
        #expect(providers.refocusCount == 1)
    }

    /// The inspected owner is the destination's one setting with a documented
    /// default, so it is what the sidebar dot and "Reset all" act on — reached
    /// through the provider-backed actions, never by constructing a panel.
    @Test @MainActor
    func overrideTracksTheInspectedOwnerAndResetRestoresIt() throws {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(
            DestinationRegistry.destination(id: "inventoryEquipment")?.overrides
        )
        #expect(!overrides.isOverridden(context))

        providers.inventoryEquipmentInspectionTarget = .player
        #expect(overrides.isOverridden(context))

        overrides.resetToDefaults(context)
        #expect(!overrides.isOverridden(context))
        #expect(providers.inventoryEquipmentInspectionTarget == .nearestActor)
    }

    /// Granting is a world change, which `World > Runtime State` owns
    /// resetting. It must never light this destination's dot, or the same
    /// delta would have two owners.
    @Test @MainActor
    func grantingIsNotAnOverride() throws {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(
            DestinationRegistry.destination(id: "inventoryEquipment")?.overrides
        )

        providers.grantItem(FakeWorldProviders.grantedSword, count: 5, to: .player)
        #expect(providers.inventoryEquipment.playerCount == 6)
        #expect(!overrides.isOverridden(context))

        overrides.resetToDefaults(context)
        #expect(providers.inventoryEquipment.playerCount == 6)
    }
}
