// World > System Menu > Menu: opens the engine's menu stack and drives the
// Resume / Settings / Quit selector (M8.5.1). Every button routes the same
// `MenuInputEvent` the keyboard produces in menu mode, so the panel cannot
// diverge from live input.

import AppKit

final class SystemMenuSection: PanelSectionViewController {
    weak var provider: (any SystemMenuControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let openControl = NSButton(title: "Open", target: nil, action: nil)
    let resumeControl = NSButton(title: "Resume", target: nil, action: nil)
    let upControl = NSButton(title: "Up", target: nil, action: nil)
    let downControl = NSButton(title: "Down", target: nil, action: nil)
    let activateControl = NSButton(title: "Activate", target: nil, action: nil)
    let movieControl = NSButton(
        checkboxWithTitle: "Vanilla menu movie", target: nil, action: nil
    )
    private let statsLabel = PanelComponents.statsLabel(identifier: "SystemMenuStatsLabel")

    var statsReadout: String {
        statsLabel.stringValue
    }

    override var sectionTitle: String {
        "Menu"
    }

    override var sectionIdentifier: String {
        "systemMenu"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    /// An open menu pauses world sim, and the movie takes the SWF layer from the
    /// gameplay HUD. Both are states a user must be able to see and clear from
    /// the sidebar without hunting for the control that set them.
    static func isOverridden(provider: (any SystemMenuControlProviding)?) -> Bool {
        guard let provider else { return false }
        return provider.systemMenuIsOpen || provider.systemMenuMovieEnabled
    }

    static func resetToDefaults(provider: (any SystemMenuControlProviding)?) {
        guard let provider else { return }
        provider.closeSystemMenu()
        provider.systemMenuMovieEnabled = false
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.group([
                PanelComponents.buttonRow([openControl, resumeControl]),
                PanelComponents.buttonRow([upControl, downControl, activateControl])
            ]),
            PanelComponents.group([movieControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        movieControl.state = provider?.systemMenuMovieEnabled == true ? .on : .off
        syncEnablement()
    }

    override func refreshReadout() {
        guard let snapshot = provider?.systemMenuSnapshot else {
            statsLabel.stringValue = "System menu: unavailable"
            syncEnablement()
            return
        }
        statsLabel.stringValue = Self.readout(for: snapshot)
        // The menu also opens and closes from live keyboard input, so button
        // enablement has to follow the readout tick, not just control actions.
        syncEnablement()
    }

    private func syncEnablement() {
        let isOpen = provider?.systemMenuIsOpen == true
        openControl.isEnabled = provider != nil && !isOpen
        for control: NSControl in [resumeControl, upControl, downControl, activateControl] {
            control.isEnabled = isOpen
        }
        movieControl.isEnabled = provider != nil
    }

    /// Pure so the readout is unit-testable without AppKit state.
    static func readout(for snapshot: SystemMenuControlSnapshot) -> String {
        guard snapshot.isOpen else {
            return "System menu: closed · world sim running"
        }
        let rows = snapshot.entryTitles.enumerated().map { index, title in
            (index == snapshot.selectedIndex ? "> " : "  ") + title
        }.joined(separator: "\n")
        let sim = snapshot.worldSimPaused ? "paused" : "running"
        let stack = snapshot.openMenus.isEmpty ? "none" : snapshot.openMenus.joined(separator: ", ")
        let outcome = snapshot.lastOutcome.map { "\nLast action: \($0)" } ?? ""
        return """
        System menu: open · world sim \(sim)
        Stack: \(stack)
        \(rows)\(outcome)
        \(movieReadout(for: snapshot))
        """
    }

    static func movieReadout(for snapshot: SystemMenuControlSnapshot) -> String {
        guard snapshot.movieEnabled else {
            return "Movie: off (engine-drawn selector)"
        }
        if let error = snapshot.movieError {
            return "Movie: failed · \(error)"
        }
        guard snapshot.movieLoaded else {
            return "Movie: not loaded"
        }
        // Print the actual `SystemPage` rows so the verification surface proves
        // the correct vanilla movie was driven.
        let rows = snapshot.movieEntryTitles.isEmpty
            ? "no rows"
            : snapshot.movieEntryTitles.joined(separator: ", ")
        return "Movie: \(SystemMenuMovieBridge.moviePath) · "
            + "state \(snapshot.movieState ?? "unknown") · "
            + "\(snapshot.movieDrawStats.drawCalls) draws · "
            + "\(snapshot.movieFaults) faults · "
            + "\(snapshot.movieMissingNames) missing names"
            + "\nMovie rows: \(rows)"
    }

    private func configureControls() {
        configure(openControl, action: #selector(openTapped), id: "SystemMenuOpenControl")
        configure(resumeControl, action: #selector(resumeTapped), id: "SystemMenuResumeControl")
        configure(upControl, action: #selector(upTapped), id: "SystemMenuUpControl")
        configure(downControl, action: #selector(downTapped), id: "SystemMenuDownControl")
        configure(
            activateControl, action: #selector(activateTapped), id: "SystemMenuActivateControl"
        )
        PanelComponents.configureCheckbox(
            movieControl, target: self, action: #selector(movieChanged),
            identifier: "SystemMenuMovieControl"
        )
    }

    private func configure(_ control: NSButton, action: Selector, id: String) {
        PanelComponents.configureButton(
            control, target: self, action: action, identifier: id
        )
    }

    @objc private func openTapped() {
        provider?.openSystemMenu()
        finishInteraction()
    }

    @objc private func resumeTapped() {
        provider?.closeSystemMenu()
        finishInteraction()
    }

    @objc private func upTapped() {
        provider?.sendSystemMenuInput(.move(.up))
        finishInteraction()
    }

    @objc private func downTapped() {
        provider?.sendSystemMenuInput(.move(.down))
        finishInteraction()
    }

    @objc private func activateTapped() {
        provider?.sendSystemMenuInput(.button(.accept))
        finishInteraction()
    }

    @objc private func movieChanged() {
        provider?.systemMenuMovieEnabled = movieControl.state == .on
        finishInteraction()
    }
}
