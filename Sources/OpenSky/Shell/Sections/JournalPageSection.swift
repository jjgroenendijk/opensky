// World > Quests & Journal > Page: open the vanilla journal, drive it, and read
// what its Quests page built. An open journal pauses the world, so this section
// carries the override and the sidebar reset closes it.

import AppKit
import OpenSkyMenus

final class JournalPageSection: PanelSectionViewController {
    weak var provider: (any JournalControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let openControl = NSButton(title: "Open journal", target: nil, action: nil)
    let closeControl = NSButton(title: "Close", target: nil, action: nil)
    let upControl = NSButton(title: "Up", target: nil, action: nil)
    let downControl = NSButton(title: "Down", target: nil, action: nil)
    let activateControl = NSButton(title: "Activate", target: nil, action: nil)
    let completedControl = NSButton(
        checkboxWithTitle: "Show completed quests", target: nil, action: nil
    )

    private let statsLabel = PanelComponents.statsLabel(identifier: "JournalPageStatsLabel")

    override var sectionTitle: String {
        "Page"
    }

    override var sectionIdentifier: String {
        "journalPage"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    /// Destination-level overridden-ness, which `DestinationRegistry` reads for
    /// the sidebar dot. An open journal pauses the world; nothing else here
    /// leaves a setting behind.
    static func isOverridden(provider: (any JournalControlProviding)?) -> Bool {
        provider?.journalSnapshot.isOpen ?? false
    }

    /// The destination's reset: hand the world back.
    static func resetToDefaults(provider: (any JournalControlProviding)?) {
        provider?.closeJournal()
    }

    override func makeContentViews() -> [NSView] {
        openControl.toolTip = "Opens the journal on the Quests page. Key: J."
        configureControls()
        return [
            PanelComponents.buttonRow([openControl, closeControl]),
            PanelComponents.buttonRow([upControl, downControl, activateControl]),
            PanelComponents.group([completedControl]),
            statsLabel
        ]
    }

    // MARK: Actions

    @objc private func open() {
        provider?.openJournal()
        refreshReadout()
        finishInteraction()
    }

    @objc private func close() {
        provider?.closeJournal()
        refreshReadout()
        finishInteraction()
    }

    @objc private func selectPrevious() {
        send(.move(.up))
    }

    @objc private func selectNext() {
        send(.move(.down))
    }

    @objc private func activate() {
        send(.button(.accept))
    }

    @objc private func toggleCompleted() {
        provider?.setJournalShowsCompleted(completedControl.state == .on)
        refreshReadout()
        finishInteraction()
    }

    private func send(_ event: MenuInputEvent) {
        provider?.sendJournalInput(event)
        refreshReadout()
        finishInteraction()
    }

    // MARK: Sync and readout

    private func configureControls() {
        PanelComponents.configureButton(
            openControl, target: self, action: #selector(open),
            identifier: "JournalOpenControl"
        )
        PanelComponents.configureButton(
            closeControl, target: self, action: #selector(close),
            identifier: "JournalCloseControl"
        )
        PanelComponents.configureButton(
            upControl, target: self, action: #selector(selectPrevious),
            identifier: "JournalUpControl"
        )
        PanelComponents.configureButton(
            downControl, target: self, action: #selector(selectNext),
            identifier: "JournalDownControl"
        )
        PanelComponents.configureButton(
            activateControl, target: self, action: #selector(activate),
            identifier: "JournalActivateControl"
        )
        PanelComponents.configureCheckbox(
            completedControl, target: self, action: #selector(toggleCompleted),
            identifier: "JournalShowCompletedControl"
        )
    }

    override func syncControls() {
        completedControl.state = provider?.journalSnapshot.showsCompleted == true ? .on : .off
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Journal: unavailable"
            return
        }
        statsLabel.stringValue = JournalReadout.movieText(for: provider.journalSnapshot)
    }
}
