// World > Runtime State > Save & Load: write the store to a named slot and
// read it back. Never overridden: "Reset all" must not delete saves. Errors
// show verbatim so a screenshot of a failed save stays diagnosable.

import AppKit
import OpenSkyWorld

final class RuntimeStateSaveSection: PanelSectionViewController {
    /// Slot the field starts on, so the acceptance round trip needs no typing.
    nonisolated static let defaultSlotName = "quick"

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
        saveControl.toolTip = "Saves runtime changes only."
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

    nonisolated static func outcomeText(_ outcome: RuntimeStateSaveOutcome) -> String {
        switch outcome {
        case .none:
            "Nothing saved or loaded this session."
        case let .running(operation, slot):
            "Running \(operation) of \(slot)..."
        case let .saved(slot):
            "Saved to \(slot)."
        case let .loaded(slot):
            "Loaded \(slot)."
        case let .failed(operation, message):
            "\(operation) failed: \(message)"
        }
    }
}
