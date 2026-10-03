// Developer > Agent Control: the server switch, the simulation pause and step,
// and a readout of the socket, the clients, and the last commands.

import AppKit
import OpenSkyAgentControl

final class AgentControlSection: PanelSectionViewController {
    weak var provider: (any AgentControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(
        checkboxWithTitle: "Agent control server",
        target: nil,
        action: nil
    )
    let pausedControl = NSButton(checkboxWithTitle: "Pause simulation", target: nil, action: nil)
    let stepControl = NSButton(title: "Step 1 frame", target: nil, action: nil)
    let statsLabel = PanelComponents.statsLabel(identifier: "AgentControlStatsLabel")
    let commandsLabel = PanelComponents.statsLabel(identifier: "AgentRecentCommandsLabel")

    override var sectionTitle: String {
        "Agent Control"
    }

    override var sectionIdentifier: String {
        "agentControl"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    /// Only the pause changes the game; the server switch does not.
    static func isOverridden(provider: (any AgentControlProviding)?) -> Bool {
        provider?.isAgentSimulationPaused ?? false
    }

    static func resetToDefaults(provider: (any AgentControlProviding)?) {
        provider?.isAgentSimulationPaused = false
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "AgentControlEnabledControl"
        )
        enabledControl.toolTip = "Lets openskycli drive this game through a local socket."
        PanelComponents.configureCheckbox(
            pausedControl, target: self, action: #selector(pausedChanged),
            identifier: "AgentSimulationPausedControl"
        )
        pausedControl.toolTip = "Freezes the simulation clock. The window keeps drawing."
        PanelComponents.configureButton(
            stepControl, target: self, action: #selector(step),
            identifier: "AgentStepControl"
        )
        stepControl.toolTip = "Pauses, then advances the simulation by one 1/60 s frame."
        return [
            PanelComponents.group([
                enabledControl,
                pausedControl,
                PanelComponents.buttonRow([stepControl])
            ]),
            statsLabel,
            PanelComponents.caption("Recent commands"),
            commandsLabel
        ]
    }

    override func syncControls() {
        let snapshot = provider?.agentControlSnapshot
        enabledControl.isEnabled = provider != nil
        enabledControl.state = snapshot?.enabled == true ? .on : .off
        let hasWorld = snapshot?.timeline != nil
        pausedControl.isEnabled = hasWorld
        pausedControl.state = snapshot?.timeline?.paused == true ? .on : .off
        stepControl.isEnabled = hasWorld
    }

    @objc private func enabledChanged() {
        provider?.isAgentControlEnabled = enabledControl.state == .on
        finishInteraction()
    }

    @objc private func pausedChanged() {
        provider?.isAgentSimulationPaused = pausedControl.state == .on
        finishInteraction()
    }

    @objc private func step() {
        provider?.stepAgentSimulation(frames: 1)
        finishInteraction()
    }

    override func refreshReadout() {
        guard let snapshot = provider?.agentControlSnapshot else {
            statsLabel.stringValue = "Agent control: unavailable"
            commandsLabel.stringValue = ""
            return
        }
        statsLabel.stringValue = Self.readoutLines(snapshot).joined(separator: "\n")
        commandsLabel.stringValue = snapshot.recentCommands.isEmpty
            ? "Commands: none"
            : snapshot.recentCommands.reversed().joined(separator: "\n")
    }

    static func readoutLines(_ snapshot: AgentControlSnapshot) -> [String] {
        var lines = [
            "Server: \(snapshot.enabled ? "on" : "off")",
            "Socket: \(snapshot.socketPath)",
            "Clients: \(snapshot.connections)"
        ]
        if let timeline = snapshot.timeline {
            let state = timeline.paused ? "paused" : "running"
            lines.append("Frame: \(timeline.frame), \(state)")
            lines.append("Steps queued: \(timeline.pendingSteps)")
            lines.append("Time scale: \(timeline.scale.formatted())")
        } else {
            lines.append("Game: not running")
        }
        if let error = snapshot.lastError {
            lines.append("Error: \(error)")
        }
        return lines
    }
}
