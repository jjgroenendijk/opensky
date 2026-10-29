// The "Agent control" switch: whether the app opens the socket `openskycli game` talks
// to (docs/tools/agent-control.md). Developer tooling, so it shows with "Show details".

import AppKit
import OpenSkyGameData

extension SettingsViewController {
    func makeAgentControlGroup() -> NSView {
        PanelComponents.configureCheckbox(
            agentControlCheckbox, target: self, action: #selector(agentControlChanged),
            identifier: "SettingsAgentControlControl"
        )
        agentControlCheckbox.toolTip = "Let openskycli game inspect and drive this app"
        return layout.detail(layout.group("Developer", [layout.toggle(agentControlCheckbox)]))
    }

    func refreshAgentControl() {
        agentControlCheckbox.state = playerSettings().bool(.agentControl) ? .on : .off
    }

    @objc func agentControlChanged() {
        playerSettings().set(.agentControl, to: agentControlCheckbox.state == .on ? 1 : 0)
        NotificationCenter.default.post(name: AgentControlHost.settingChanged, object: nil)
    }
}
