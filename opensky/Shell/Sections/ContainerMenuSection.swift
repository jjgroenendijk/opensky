// World > Container Menu > Menu: opens the engine's menu stack on a container
// or a merchant and drives the two-pane transfer list (M12.2.3, issue #179).
// Every button routes the same `MenuInputEvent` the keyboard produces in menu
// mode, so the panel cannot diverge from live input.

import AppKit

final class ContainerMenuSection: PanelSectionViewController {
    weak var provider: (any ContainerMenuControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let openControl = NSButton(title: "Open", target: nil, action: nil)
    let closeControl = NSButton(title: "Close", target: nil, action: nil)
    let upControl = NSButton(title: "Up", target: nil, action: nil)
    let downControl = NSButton(title: "Down", target: nil, action: nil)
    let switchSideControl = NSButton(title: "Switch side", target: nil, action: nil)
    let transferControl = NSButton(title: "Transfer", target: nil, action: nil)
    let takeAllControl = NSButton(title: "Take all", target: nil, action: nil)
    let barterControl = NSButton(
        checkboxWithTitle: "Barter mode (merchant)", target: nil, action: nil
    )
    let movieControl = NSButton(
        checkboxWithTitle: "Vanilla menu movie", target: nil, action: nil
    )
    private let statsLabel = PanelComponents.statsLabel(identifier: "ContainerMenuStatsLabel")

    var statsReadout: String {
        statsLabel.stringValue
    }

    override var sectionTitle: String {
        "Menu"
    }

    override var sectionIdentifier: String {
        "containerMenu"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    /// An open menu pauses world sim, barter mode swaps which vanilla movie the
    /// menu is, and the movie takes the SWF layer from the gameplay HUD. All
    /// three are states a user must be able to see and clear from the sidebar.
    static func isOverridden(provider: (any ContainerMenuControlProviding)?) -> Bool {
        guard let provider else { return false }
        return provider.containerMenuIsOpen
            || provider.containerMenuMovieEnabled
            || provider.containerMenuMode == .barter
    }

    static func resetToDefaults(provider: (any ContainerMenuControlProviding)?) {
        guard let provider else { return }
        provider.closeContainerMenu()
        provider.containerMenuMovieEnabled = false
        provider.containerMenuMode = .container
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.group([
                PanelComponents.buttonRow([openControl, closeControl]),
                PanelComponents.buttonRow([upControl, downControl]),
                PanelComponents.buttonRow([switchSideControl, transferControl]),
                PanelComponents.buttonRow([takeAllControl])
            ]),
            PanelComponents.group([barterControl, movieControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        barterControl.state = provider?.containerMenuMode == .barter ? .on : .off
        movieControl.state = provider?.containerMenuMovieEnabled == true ? .on : .off
        syncEnablement()
    }

    override func refreshReadout() {
        guard let snapshot = provider?.containerMenuSnapshot else {
            statsLabel.stringValue = "Container menu: unavailable"
            syncEnablement()
            return
        }
        statsLabel.stringValue = Self.readout(for: snapshot)
        transferControl.title = snapshot.transferLabel
        // The menu also opens and closes from live keyboard input, so button
        // enablement has to follow the readout tick, not just control actions.
        syncEnablement()
    }

    private func syncEnablement() {
        let isOpen = provider?.containerMenuIsOpen == true
        openControl.isEnabled = provider != nil && !isOpen
        for control in [closeControl, upControl, downControl, switchSideControl, transferControl] {
            control.isEnabled = isOpen
        }
        // Take all is a container action: a merchant does not hand over stock.
        takeAllControl.isEnabled = isOpen && provider?.containerMenuMode == .container
        barterControl.isEnabled = provider != nil
        movieControl.isEnabled = provider != nil
    }

    /// Pure so the readout is unit-testable without AppKit state.
    static func readout(for snapshot: ContainerMenuControlSnapshot) -> String {
        guard snapshot.isOpen else {
            return "Container menu: closed · \(snapshot.mode.rawValue) mode · world sim running"
        }
        let sim = snapshot.worldSimPaused ? "paused" : "running"
        let stack = snapshot.openMenus.isEmpty ? "none" : snapshot.openMenus.joined(separator: ", ")
        let action = snapshot.lastActionText.map { "\nLast action: \($0)" } ?? ""
        return """
        Container menu: open · \(snapshot.mode.rawValue) mode · world sim \(sim)
        Stack: \(stack)
        \(sideLine(for: snapshot))
        \(rows(for: snapshot))
        \(goldLine(for: snapshot))\(action)
        \(movieReadout(for: snapshot))
        """
    }

    static func sideLine(for snapshot: ContainerMenuControlSnapshot) -> String {
        let container = snapshot.containerName ?? "no container"
        let side = snapshot.side == .container ? container : "Player"
        return "Showing: \(side) · \(snapshot.transferLabel) moves the selected row"
    }

    static func rows(for snapshot: ContainerMenuControlSnapshot) -> String {
        guard !snapshot.entryLines.isEmpty else {
            return "  (this side is empty)"
        }
        return snapshot.entryLines.enumerated().map { index, line in
            (index == snapshot.selectedIndex ? "> " : "  ") + line
        }.joined(separator: "\n")
    }

    /// Both purses plus the price of the selected row, which is the number a
    /// barter run is actually verified against.
    static func goldLine(for snapshot: ContainerMenuControlSnapshot) -> String {
        let purses = "Gold: player \(snapshot.playerGold) · "
            + "\(snapshot.containerName ?? "container") \(snapshot.containerGold)"
        guard let price = snapshot.selectedPrice else {
            return purses
        }
        let affordable = snapshot.canAffordSelection ? "" : " (cannot pay)"
        return purses + "\n\(snapshot.transferLabel) price: \(price) gold\(affordable)"
    }

    static func movieReadout(for snapshot: ContainerMenuControlSnapshot) -> String {
        guard snapshot.movieEnabled else {
            return "Movie: off (engine-drawn row list)"
        }
        if let error = snapshot.movieError {
            return "Movie: failed · \(error)"
        }
        guard snapshot.movieLoaded else {
            return "Movie: not loaded"
        }
        let rows = snapshot.movieEntryTitles.isEmpty
            ? "no rows"
            : snapshot.movieEntryTitles.joined(separator: ", ")
        return "Movie: \(ContainerMenuMovieBridge.moviePath(for: snapshot.mode)) · "
            + "\(snapshot.movieDrawStats.drawCalls) draws · "
            + "\(snapshot.movieFaults) faults · "
            + "\(snapshot.movieMissingNames) missing names · "
            + "\(snapshot.movieUnhandledInvokes) unhandled invokes"
            + "\nMovie vendor gold: \(snapshot.movieVendorGold ?? "absent")"
            + "\nMovie rows: \(rows)"
    }

    private func configureControls() {
        configure(openControl, action: #selector(openTapped), id: "ContainerMenuOpenControl")
        configure(closeControl, action: #selector(closeTapped), id: "ContainerMenuCloseControl")
        configure(upControl, action: #selector(upTapped), id: "ContainerMenuUpControl")
        configure(downControl, action: #selector(downTapped), id: "ContainerMenuDownControl")
        configure(
            switchSideControl, action: #selector(switchSideTapped),
            id: "ContainerMenuSwitchSideControl"
        )
        configure(
            transferControl, action: #selector(transferTapped),
            id: "ContainerMenuTransferControl"
        )
        configure(
            takeAllControl, action: #selector(takeAllTapped), id: "ContainerMenuTakeAllControl"
        )
        PanelComponents.configureCheckbox(
            barterControl, target: self, action: #selector(barterChanged),
            identifier: "ContainerMenuBarterControl"
        )
        PanelComponents.configureCheckbox(
            movieControl, target: self, action: #selector(movieChanged),
            identifier: "ContainerMenuMovieControl"
        )
    }

    private func configure(_ control: NSButton, action: Selector, id: String) {
        PanelComponents.configureButton(control, target: self, action: action, identifier: id)
    }

    @objc private func openTapped() {
        provider?.openContainerMenu()
        finishInteraction()
    }

    @objc private func closeTapped() {
        provider?.closeContainerMenu()
        finishInteraction()
    }

    @objc private func upTapped() {
        provider?.sendContainerMenuInput(.move(.up))
        finishInteraction()
    }

    @objc private func downTapped() {
        provider?.sendContainerMenuInput(.move(.down))
        finishInteraction()
    }

    @objc private func switchSideTapped() {
        provider?.switchContainerMenuSide()
        finishInteraction()
    }

    @objc private func transferTapped() {
        provider?.activateContainerMenuSelection()
        finishInteraction()
    }

    @objc private func takeAllTapped() {
        provider?.takeAllFromContainerMenu()
        finishInteraction()
    }

    @objc private func barterChanged() {
        provider?.containerMenuMode = barterControl.state == .on ? .barter : .container
        finishInteraction()
    }

    @objc private func movieChanged() {
        provider?.containerMenuMovieEnabled = movieControl.state == .on
        finishInteraction()
    }
}
