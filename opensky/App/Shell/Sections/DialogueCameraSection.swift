// World > HUD & Interaction > Dialogue Camera (issue #427, roadmap item 17.4,
// scope point 5): the discoverable half of the conversation camera and the
// speaker focus.
//
// It sits beside the Dialogue section rather than in a destination of its own
// because it is the same behaviour seen from the other end: that section starts
// a conversation, this one shows what the conversation did to the view and to
// the actor. Item 17.8 assembles the milestone's own destination, and moving a
// standalone section there is a registry edit that changes no control id.
//
// The force toggle is what makes the camera checkable without a conversation:
// a conversation needs an actor with something to say, standing within the
// interaction ray's reach, and the framing has to be checkable against any
// actor in the cell.

import AppKit

final class DialogueCameraSection: PanelSectionViewController {
    weak var provider: (any DialogueCameraControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    /// The selectors, in popup row order.
    static let targets = DialogueCameraTarget.allCases

    let forceControl = NSButton(
        checkboxWithTitle: "Force the dialogue camera", target: nil, action: nil
    )
    let targetControl = NSPopUpButton()
    let overlayControl = NSButton(
        checkboxWithTitle: "Draw the camera gizmo", target: nil, action: nil
    )

    private let cameraLabel = PanelComponents.statsLabel(
        identifier: "DialogueCameraStatsLabel"
    )
    private let speakerLabel = PanelComponents.statsLabel(
        identifier: "DialogueCameraSpeakerStatsLabel"
    )

    var cameraReadout: String {
        cameraLabel.stringValue
    }

    var speakerReadout: String {
        speakerLabel.stringValue
    }

    override var sectionTitle: String {
        "Dialogue Camera"
    }

    override var sectionIdentifier: String {
        "dialogueCamera"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    /// Both switches default off. A camera engaged by a conversation is not
    /// overridden-ness — the conversation owns it, and "Reset all" must not
    /// close a conversation the user is holding.
    static func isOverridden(provider: (any DialogueCameraControlProviding)?) -> Bool {
        guard let provider else { return false }
        return provider.isDialogueCameraForced || provider.dialogueCameraOverlayEnabled
    }

    static func resetToDefaults(provider: (any DialogueCameraControlProviding)?) {
        provider?.isDialogueCameraForced = false
        provider?.dialogueCameraOverlayEnabled = false
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.note(
                "A conversation takes the view without changing the camera mode: it frames "
                    + "the speaker's head from the side the player is standing on, and the "
                    + "mode underneath is what the view goes back to on Leave. The speaker "
                    + "stops walking, turns to face the player and has its package "
                    + "suspended for the duration. Force engages the same camera on the "
                    + "selected actor with no conversation open, so the framing and the "
                    + "turn can be checked against any actor in the cell."
            ),
            PanelComponents.group([
                forceControl,
                PanelComponents.labeledFieldRow(
                    caption: "Target", captionWidth: 70, field: targetControl
                ),
                overlayControl
            ]),
            cameraLabel,
            speakerLabel
        ]
    }

    // MARK: Actions

    @objc private func forceChanged() {
        provider?.isDialogueCameraForced = forceControl.state == .on
        refreshReadout()
        finishInteraction()
    }

    @objc private func targetChanged() {
        let index = targetControl.indexOfSelectedItem
        guard Self.targets.indices.contains(index) else { return }
        provider?.dialogueCameraTarget = Self.targets[index]
        refreshReadout()
        finishInteraction()
    }

    @objc private func overlayChanged() {
        provider?.dialogueCameraOverlayEnabled = overlayControl.state == .on
        refreshReadout()
        finishInteraction()
    }

    // MARK: Sync and readout

    private func configureControls() {
        PanelComponents.configureCheckbox(
            forceControl, target: self, action: #selector(forceChanged),
            identifier: "DialogueCameraForceControl"
        )
        PanelComponents.configureCheckbox(
            overlayControl, target: self, action: #selector(overlayChanged),
            identifier: "DialogueCameraOverlayControl"
        )
        PanelComponents.configurePopUp(
            targetControl, target: self, action: #selector(targetChanged),
            identifier: "DialogueCameraTargetControl"
        )
        targetControl.removeAllItems()
        targetControl.addItems(withTitles: Self.targets.map(\.label))
    }

    override func syncControls() {
        let available = provider != nil
        forceControl.isEnabled = available
        overlayControl.isEnabled = available
        targetControl.isEnabled = available
        guard let provider else { return }
        forceControl.state = provider.isDialogueCameraForced ? .on : .off
        overlayControl.state = provider.dialogueCameraOverlayEnabled ? .on : .off
        targetControl.selectItem(
            at: Self.targets.firstIndex(of: provider.dialogueCameraTarget) ?? 0
        )
    }

    override func refreshReadout() {
        guard let snapshot = provider?.dialogueCameraSnapshot else {
            cameraLabel.stringValue = "Dialogue camera: unavailable"
            speakerLabel.stringValue = ""
            return
        }
        cameraLabel.stringValue = DialogueCameraReadout.cameraText(for: snapshot)
            + "\n" + DialogueCameraReadout.outcomeText(for: snapshot)
        speakerLabel.stringValue = DialogueCameraReadout.speakerText(for: snapshot)
    }
}
