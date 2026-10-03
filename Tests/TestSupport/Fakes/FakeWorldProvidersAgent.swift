// The agent control part of the world-provider fake: a stored snapshot and a
// record of the steps the panel asked for.

import OpenSkyAgentControl

struct FakeAgentControlState {
    var snapshot = AgentControlSnapshot(
        enabled: false, socketPath: "/tmp/agent.sock", connections: 0, lastError: nil,
        recentCommands: [], timeline: AgentTimeline(frame: 0, paused: false)
    )
    var steps: [Int] = []
}

/// The conformance is declared by `WorldControlProviders` on the class.
extension FakeWorldProviders {
    var agentControlSnapshot: AgentControlSnapshot {
        agentControlState.snapshot
    }

    var isAgentControlEnabled: Bool {
        get { agentControlState.snapshot.enabled }
        set { agentControlState.snapshot.enabled = newValue }
    }

    var isAgentSimulationPaused: Bool {
        get { agentControlState.snapshot.timeline?.paused ?? false }
        set { agentControlState.snapshot.timeline?.paused = newValue }
    }

    func stepAgentSimulation(frames: Int) {
        agentControlState.steps.append(frames)
        agentControlState.snapshot.timeline?.paused = true
    }
}
