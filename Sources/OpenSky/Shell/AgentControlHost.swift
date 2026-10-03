// Runs the agent control server for the app's lifetime and points it at the
// running mode's game. Off unless the launch environment or the sidebar turns
// it on (docs/tools/agent-control.md).

import AppKit
import OpenSkyAgentControl
import OpenSkyGameData
import OpenSkyLaunch

final class AgentControlHost {
    /// `openskycli game launch` sets this to 1.
    static let environmentKey = "OPENSKY_AGENT_CONTROL"
    /// Faster than the display, so a step reply leaves in the frame it finished.
    static let pollInterval = 1.0 / 240

    let coordinator: AgentControlCoordinator
    private var timer: Timer?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        coordinator = AgentControlCoordinator(socketPath: AgentSocketLocation
            .path(environment: environment))
        coordinator.appVersion = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "dev"
        coordinator.onEnabledChange = { [weak self] enabled in
            if enabled {
                self?.startPolling()
            } else {
                self?.stopPolling()
            }
        }
        if environment[Self.environmentKey] == "1" {
            coordinator.setEnabled(true)
        }
    }

    func attach(game: GameViewController, mode: LaunchMode, root: GameDataRoot?) {
        game.agentWorld.dataRoot = root
        game.agentWorld.modeName = mode.rawValue
        game.agentControl = coordinator
        coordinator.attach(world: game.agentWorld)
    }

    /// Removes the socket file on a normal quit.
    func shutdown() {
        coordinator.setEnabled(false)
    }

    private func startPolling() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.coordinator.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
