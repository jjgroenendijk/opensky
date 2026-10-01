// World > HUD & Interaction > Dialogue: the listed control for Talk. Open
// dialogue calls the same `openDialogue()` as the F key, and Up, Down, Choose,
// and Leave send the same `MenuInputEvent` as the live keys.

import AppKit
import OpenSkyMenus

final class DialogueSection: PanelSectionViewController {
    weak var provider: (any DialogueControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let openControl = NSButton(title: "Open dialogue", target: nil, action: nil)
    let leaveControl = NSButton(title: "Leave", target: nil, action: nil)
    let upControl = NSButton(title: "Up", target: nil, action: nil)
    let downControl = NSButton(title: "Down", target: nil, action: nil)
    let chooseControl = NSButton(title: "Choose", target: nil, action: nil)

    private let topicsLabel = PanelComponents.statsLabel(
        identifier: "DialogueTopicsStatsLabel"
    )
    private let conditionsLabel = PanelComponents.statsLabel(
        identifier: "DialogueConditionsStatsLabel"
    )
    private let movieLabel = PanelComponents.statsLabel(
        identifier: "DialogueMovieStatsLabel"
    )

    var topicsReadout: String {
        topicsLabel.stringValue
    }

    var conditionsReadout: String {
        conditionsLabel.stringValue
    }

    override var sectionTitle: String {
        "Dialogue"
    }

    override var sectionIdentifier: String {
        "dialogue"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    /// An open conversation is this section's only overridden-ness: it holds
    /// the engine menu stack. It does *not* pause the world, which is the point
    /// of the milestone and what the readout states.
    static func isOverridden(provider: (any DialogueControlProviding)?) -> Bool {
        provider?.dialogueSnapshot.isOpen ?? false
    }

    /// The reset: leave the conversation.
    static func resetToDefaults(provider: (any DialogueControlProviding)?) {
        provider?.closeDialogue()
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.note(
                "Opens the vanilla dialoguemenu.swf on the actor under the crosshair and "
                    + "fills it from the dialogue runtime. F does the same thing in world "
                    + "mode, on a living, non-hostile actor within reach. Unlike every "
                    + "other menu this one leaves the world simulating, which the menu "
                    + "stack line below reports. Up, Down, Choose and Leave go through the "
                    + "same input path as the live keys."
            ),
            PanelComponents.buttonRow([openControl, leaveControl]),
            PanelComponents.buttonRow([upControl, downControl, chooseControl]),
            topicsLabel,
            conditionsLabel,
            movieLabel
        ]
    }

    // MARK: Actions

    @objc private func open() {
        provider?.openDialogue()
        refreshReadout()
        finishInteraction()
    }

    @objc private func leave() {
        provider?.closeDialogue()
        refreshReadout()
        finishInteraction()
    }

    @objc private func selectPrevious() {
        send(.move(.up))
    }

    @objc private func selectNext() {
        send(.move(.down))
    }

    @objc private func choose() {
        send(.button(.accept))
    }

    private func send(_ event: MenuInputEvent) {
        provider?.sendDialogueInput(event)
        refreshReadout()
        finishInteraction()
    }

    // MARK: Sync and readout

    private func configureControls() {
        PanelComponents.configureButton(
            openControl, target: self, action: #selector(open),
            identifier: "DialogueOpenControl"
        )
        PanelComponents.configureButton(
            leaveControl, target: self, action: #selector(leave),
            identifier: "DialogueLeaveControl"
        )
        PanelComponents.configureButton(
            upControl, target: self, action: #selector(selectPrevious),
            identifier: "DialogueUpControl"
        )
        PanelComponents.configureButton(
            downControl, target: self, action: #selector(selectNext),
            identifier: "DialogueDownControl"
        )
        PanelComponents.configureButton(
            chooseControl, target: self, action: #selector(choose),
            identifier: "DialogueChooseControl"
        )
    }

    override func refreshReadout() {
        guard let snapshot = provider?.dialogueSnapshot else {
            topicsLabel.stringValue = "Dialogue: unavailable"
            conditionsLabel.stringValue = ""
            movieLabel.stringValue = ""
            return
        }
        topicsLabel.stringValue = DialogueReadout.topicsText(for: snapshot)
            + "\n" + DialogueReadout.outcomeText(for: snapshot)
        conditionsLabel.stringValue = DialogueReadout.conditionsText(for: snapshot)
        movieLabel.stringValue = DialogueReadout.movieText(for: snapshot)
    }
}
