// World > Runtime State > Save & Load section (M10.1.5): writes the world-state
// store to a named slot and reads it back, which is the round trip the milestone
// acceptance drives.
//
// Never overridden: a save on disk is not a panel setting, and "Reset all"
// clearing the user's saves would be destructive rather than restorative.
// Failures are shown verbatim — the provider hands back the thrown error's own
// description, and a paraphrase would make a failed save undiagnosable from a
// screenshot.

import AppKit

final class RuntimeStateSaveSection: PanelSectionViewController {
    /// Slot the field starts on, so the acceptance round trip needs no typing.
    static let defaultSlotName = "quick"

    weak var provider: (any RuntimeStateControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let slotControl = NSTextField(string: RuntimeStateSaveSection.defaultSlotName)
    let saveControl = NSButton(title: "Save", target: nil, action: nil)
    let loadControl = NSButton(title: "Load", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "RuntimeStateSaveStatsLabel")

    override var sectionTitle: String {
        "Save & Load"
    }

    override var sectionIdentifier: String {
        "runtimeStateSave"
    }

    var readout: String {
        statsLabel.stringValue
    }

    /// Slot name the buttons act on, falling back to the default so an emptied
    /// field cannot produce an unnamed save file.
    var slotName: String {
        let text = slotControl.stringValue.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? Self.defaultSlotName : text
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureTextField(
            slotControl, identifier: "RuntimeStateSlotControl", width: 150,
            placeholder: Self.defaultSlotName
        )
        PanelComponents.configureButton(
            saveControl, target: self, action: #selector(save),
            identifier: "RuntimeStateSaveControl"
        )
        PanelComponents.configureButton(
            loadControl, target: self, action: #selector(load),
            identifier: "RuntimeStateLoadControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.note(
                    "Saves the runtime deltas only, checked against the loaded plugins when "
                        + "read back. Loading rebuilds the resident cells from the stored "
                        + "state."
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Slot", captionWidth: 60, field: slotControl
                )
            ]),
            PanelComponents.buttonRow([saveControl, loadControl]),
            statsLabel
        ]
    }

    @objc private func save() {
        provider?.saveWorldState(slot: slotName)
        finishInteraction()
    }

    @objc private func load() {
        provider?.loadWorldState(slot: slotName)
        finishInteraction()
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Runtime state: unavailable"
            return
        }
        let slots = provider.runtimeStateSaveSlots
        statsLabel.stringValue = [
            Self.outcomeText(provider.lastSaveOutcome),
            "Slots: " + (slots.isEmpty ? "none" : slots.joined(separator: ", "))
        ].joined(separator: "\n")
    }

    static func outcomeText(_ outcome: RuntimeStateSaveOutcome) -> String {
        switch outcome {
        case .none:
            "Nothing saved or loaded this session."
        case let .saved(slot):
            "Saved to \(slot)."
        case let .loaded(slot):
            "Loaded \(slot)."
        case let .failed(operation, message):
            "\(operation) failed: \(message)"
        }
    }
}
