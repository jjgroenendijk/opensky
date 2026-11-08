// Runs the agent control server for the app's lifetime and points it at the
// running game. The "Agent control" setting turns it on; the launch environment
// can override it (docs/tools/agent-control.md).

import AppKit
import OpenSkyAgentControl
import OpenSkyGameData
import OpenSkyLaunch

final class AgentControlHost {
    /// The Settings page posts this after it changes the "Agent control" setting.
    static let settingChanged = Notification.Name("OpenSkyAgentControlSettingChanged")
    /// Faster than the display, so a step reply leaves in the frame it finished.
    static let pollInterval = 1.0 / 240

    private(set) lazy var coordinator = AgentControlCoordinator(
        socketPath: AgentSocketLocation.path(environment: environment),
        world: { [weak self] in self?.game?.session?.agentWorld },
        enabledChanged: { [weak self] enabled in
            if enabled {
                self?.startPolling()
            } else {
                self?.stopPolling()
            }
        }
    )
    private let environment: [String: String]
    /// The game window's view controller, read on each request so a new window counts.
    private let currentGame: () -> GameViewController?
    private var game: GameViewController? {
        currentGame()
    }

    private var timer: Timer?

    init(
        currentGame: @escaping () -> GameViewController?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.currentGame = currentGame
        self.environment = environment
        coordinator.appVersion = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "dev"
        applySetting()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applySetting), name: Self.settingChanged, object: nil
        )
    }

    @objc private func applySetting() {
        let store = PlayerSettingsStore(persistence: try? PlayerSettingsFile.defaultFile())
        coordinator.setEnabled(LaunchPreferences.opensAgentControl(
            setting: store.bool(.agentControl), environment: environment
        ))
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
