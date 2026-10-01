// The progression destination, split out of DestinationRegistry.swift to stay
// under the type-length cap. It has no override actions: every control writes
// world state (a level, a skill, a perk), so "Reset all" must not touch it.

import AppKit
import OpenSkyWorld

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
