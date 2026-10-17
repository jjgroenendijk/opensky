// The crime and faction destination, split out of DestinationRegistry.swift to
// stay under the type-length cap. Its one override is the vendor faction;
// bounties and memberships are world state that "Reset all" leaves alone.

import AppKit
import OpenSkyCrime

extension DestinationRegistry {
    static let crimeDestinations: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "crimeFactions",
            title: "Crime & Factions",
            section: .world,
            symbolName: "building.columns",
            content: .worldInspector { context in
                let panel = CrimeFactionPanelViewController()
                panel.provider = context.crimeFaction
                return panel
            },
            overrides: DestinationOverrideActions(
                isOverridden: { $0.crimeFaction.vendorOverrideSelection != nil },
                resetToDefaults: { $0.crimeFaction.vendorOverrideSelection = nil }
            )
        )
    ]
}
