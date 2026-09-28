// The M20 progression destination (issue #500, roadmap item 20.7). Satellite of
// Shell/DestinationRegistry.swift, which holds every other descriptor and
// splices this one into `all` at the position it occupies in the sidebar: the
// registry enum body is at the strict-lint type-length cap, and this descriptor
// is what pushed it over.
//
// Placed at the end of the simulation destinations, after Dialogue & Voice and
// before the menus: everything above it is the world a session runs, and this is
// what the player has become while running it. The combat destination above
// answers a different question about a different subject — what an actor is
// worth in the fight it is in right now.
//
// No `DestinationOverrideActions`. Every control under this destination writes
// world state the user produced on purpose — a level, a trained skill, an owned
// perk — and none of them writes a panel setting. A sidebar dot would mean "the
// player has progressed", and a "Reset all overrides" that acted on it would
// take a character's levels away rather than restore a knob.

import AppKit

extension DestinationRegistry {
    static let progressionDestinations: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "progression",
            title: "Progression",
            section: .world,
            symbolName: "chart.line.uptrend.xyaxis",
            content: .worldInspector { context in
                let panel = ProgressionPanelViewController()
                panel.provider = context.providers
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
                return panel
            }
        )
    ]
}
