// The agent control destination. Its one override is the simulation pause; the
// server switch is a tool setting, so "Reset all" leaves it on.

import AppKit
import OpenSkyAgentControl

extension DestinationRegistry {
    static let agentDestinations: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "agentControl",
            title: "Agent Control",
            section: .developer,
            symbolName: "terminal",
            content: .worldInspector { context in
                let panel = AgentControlPanelViewController()
                panel.provider = context.providers
                return panel
            },
            overrides: DestinationOverrideActions(
                isOverridden: { AgentControlSection.isOverridden(provider: $0.providers) },
                resetToDefaults: { AgentControlSection.resetToDefaults(provider: $0.providers) }
            )
        )
    ]
}
