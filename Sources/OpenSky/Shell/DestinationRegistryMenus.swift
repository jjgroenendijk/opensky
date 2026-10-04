// The System, Character, Map, Inventory, and Container menu descriptors, split out of
// DestinationRegistry.swift to stay under the type-length cap.
// `DestinationRegistry` stays the single registration point.

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
            id: "characterMenus",
            title: "Character",
            section: .world,
            symbolName: "person.crop.square",
            content: .worldInspector { context in
                let panel = CharacterMenuPanelViewController()
                panel.provider = context.providers
                return panel
            },
            overrides: characterMenuOverrides
        ),
        DestinationDescriptor(
            id: "mapMenu",
            title: "Map",
            section: .world,
            symbolName: "map",
            content: .worldInspector { context in
                let panel = MapMenuPanelViewController()
                panel.provider = context.providers
                return panel
            },
            overrides: mapMenuOverrides
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
