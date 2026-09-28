// The three menu destinations' descriptors. Satellite of
// Shell/DestinationRegistry.swift, which holds the rest of the list and splices
// this one in at the sidebar position it occupies.
//
// The split is the same one `DestinationRegistryOverrides.swift` made and for
// the same reason: adding the M16 gate's `World > AI & Navigation` destination
// (issue #203) took the registry enum body past the strict-lint type-length cap,
// and these three rows are the part of the list that already read as one group —
// the System, Inventory and Container menus, each a vanilla movie driven through
// its own model. `DestinationRegistry` is still the single registration point;
// nothing outside these two files registers a destination.

import AppKit

extension DestinationRegistry {
    static let menuDestinations: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "systemMenu",
            title: "System Menu",
            section: .world,
            symbolName: "list.bullet.rectangle",
            content: .worldInspector { context in
                let panel = SystemMenuPanelViewController()
                panel.provider = context.providers
                return panel
            },
            overrides: systemMenuOverrides
        ),
        DestinationDescriptor(
            id: "inventoryMenu",
            title: "Inventory Menu",
            section: .world,
            symbolName: "bag",
            content: .worldInspector { context in
                let panel = InventoryMenuPanelViewController()
                panel.provider = context.providers
                return panel
            },
            overrides: inventoryMenuOverrides
        ),
        DestinationDescriptor(
            id: "containerMenu",
            title: "Container Menu",
            section: .world,
            symbolName: "shippingbox",
            content: .worldInspector { context in
                let panel = ContainerMenuPanelViewController()
                panel.provider = context.providers
                return panel
            },
            overrides: containerMenuOverrides
        )
    ]
}
