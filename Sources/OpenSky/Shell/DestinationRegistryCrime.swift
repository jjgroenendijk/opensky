// The M21 crime and faction destination (issue #507, roadmap item 21.8).
// Satellite of Shell/DestinationRegistry.swift, spliced into `all` right after
// Progression, for the reason that file gives for splitting descriptors out:
// the registry enum body is at the strict-lint type-length cap.
//
// Placed after Progression and before the menus: it is still the world a
// session runs, and a bounty, like a level, is something the player earned.
//
// The one override it registers is the vendor-faction override, which changes
// which rules the next barter trades under without changing anybody's
// memberships. Bounties and memberships are world state the user produced on
// purpose, and "Reset all overrides" leaves them alone.

import AppKit
import OpenSkyEngine

extension DestinationRegistry {
    static let crimeDestinations: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "crimeFactions",
            title: "Crime & Factions",
            section: .world,
            symbolName: "building.columns",
            content: .worldInspector { context in
                let panel = CrimeFactionPanelViewController()
                panel.provider = context.providers
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
                return panel
            },
            overrides: DestinationOverrideActions(
                isOverridden: { $0.providers.vendorOverrideSelection != nil },
                resetToDefaults: { $0.providers.vendorOverrideSelection = nil }
            )
        )
    ]
}
