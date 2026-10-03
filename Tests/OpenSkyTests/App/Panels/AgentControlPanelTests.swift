// Developer > Agent Control: ids, the server and pause toggles, the step
// button, and the readout.

import AppKit
@testable import OpenSky
import OpenSkyAgentControl
import Testing

@MainActor
struct AgentControlPanelTests {
    @Test func accessibilityIdentifiersArePinned() {
        let panel = Self.panel()
        let section = panel.controlSection
        #expect(section.sectionIdentifier == "agentControl")
        #expect(section.enabledControl.accessibilityIdentifier() == "AgentControlEnabledControl")
        #expect(section.pausedControl.accessibilityIdentifier() == "AgentSimulationPausedControl")
        #expect(section.stepControl.accessibilityIdentifier() == "AgentStepControl")
        #expect(section.statsLabel.accessibilityIdentifier() == "AgentControlStatsLabel")
        #expect(section.commandsLabel.accessibilityIdentifier() == "AgentRecentCommandsLabel")
    }

    @Test func togglesAndStepReachTheProvider() {
        let fake = FakeWorldProviders()
        let panel = Self.panel(provider: fake)
        let section = panel.controlSection

        section.enabledControl.state = .on
        send(section.enabledControl)
        #expect(fake.isAgentControlEnabled)

        section.pausedControl.state = .on
        send(section.pausedControl)
        #expect(fake.isAgentSimulationPaused)
        #expect(AgentControlSection.isOverridden(provider: fake))
        AgentControlSection.resetToDefaults(provider: fake)
        #expect(!fake.isAgentSimulationPaused)

        send(section.stepControl)
        #expect(fake.agentControlState.steps == [1])
    }

    @Test func readoutNamesTheSocketClientsFrameAndCommands() {
        let fake = FakeWorldProviders()
        fake.agentControlState.snapshot = AgentControlSnapshot(
            enabled: true, socketPath: "/tmp/agent.sock", connections: 2, lastError: nil,
            recentCommands: ["10 status", "11 time.step"],
            timeline: AgentTimeline(frame: 11, paused: true, pendingSteps: 0, scale: 1)
        )
        let panel = Self.panel(provider: fake)
        panel.controlSection.refreshReadout()
        let stats = panel.controlSection.statsLabel.stringValue
        #expect(stats.contains("Server: on"))
        #expect(stats.contains("Socket: /tmp/agent.sock"))
        #expect(stats.contains("Clients: 2"))
        #expect(stats.contains("Frame: 11, paused"))
        #expect(panel.controlSection.commandsLabel.stringValue == "11 time.step\n10 status")
    }

    @Test func withoutAGameThePauseAndStepAreDisabled() {
        let fake = FakeWorldProviders()
        fake.agentControlState.snapshot.timeline = nil
        let panel = Self.panel(provider: fake)
        panel.controlSection.syncControls()
        #expect(!panel.controlSection.pausedControl.isEnabled)
        #expect(!panel.controlSection.stepControl.isEnabled)
        #expect(panel.controlSection.enabledControl.isEnabled)
    }

    private func send(_ control: NSButton) {
        control.sendAction(control.action, to: control.target)
    }

    private static func panel(provider: FakeWorldProviders? = nil)
        -> AgentControlPanelViewController
    {
        let panel = AgentControlPanelViewController()
        panel.loadViewIfNeeded()
        if let provider {
            panel.provider = provider
        }
        return panel
    }
}
