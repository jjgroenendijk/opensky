// World > Runtime State > Change section (M10.1.5): the three mutations the
// milestone gate names — disable, enable, and a fixed transform nudge — applied
// either to whatever the interaction ray currently targets or to a FormID typed
// into the field.
//
// This section owns the target field even though the Reset section acts on the
// same reference: one field means the user cannot leave two target boxes
// disagreeing about what "the target" is. The panel hands the Reset section a
// closure reading `targetSelector` rather than duplicating the control.
//
// Not overridden. A disabled reference is world state, not a panel setting, so
// undoing it belongs to the Reset section, which owns both the dirty count and
// the reset that clears it.

import AppKit

final class RuntimeStateChangeSection: PanelSectionViewController {
    weak var provider: (any RuntimeStateControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let targetControl = NSTextField()
    let disableControl = NSButton(title: "Disable", target: nil, action: nil)
    let enableControl = NSButton(title: "Enable", target: nil, action: nil)
    let nudgeControl = NSButton(title: "Nudge +X", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(
        identifier: "RuntimeStateChangeStatsLabel"
    )

    /// Result of the most recent button press, kept across ticker refreshes so
    /// the readout does not erase what the user just did.
    private var lastActionText = "No change applied yet."

    /// The reference every mutation in this panel applies to. An empty field
    /// means "whatever I am looking at", which is the common case; anything else
    /// is handed to the provider as raw text because only the engine can resolve
    /// a load-order-relative FormID.
    var targetSelector: RuntimeStateTargetSelector {
        let text = targetControl.stringValue.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? .currentTarget : .formID(text)
    }

    override var sectionTitle: String {
        "Change"
    }

    override var sectionIdentifier: String {
        "runtimeStateChange"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureTextField(
            targetControl, identifier: "RuntimeStateTargetControl", width: 150,
            placeholder: "current target"
        )
        PanelComponents.configureButton(
            disableControl, target: self, action: #selector(disable),
            identifier: "RuntimeStateDisableControl"
        )
        PanelComponents.configureButton(
            enableControl, target: self, action: #selector(enable),
            identifier: "RuntimeStateEnableControl"
        )
        PanelComponents.configureButton(
            nudgeControl, target: self, action: #selector(nudge),
            identifier: "RuntimeStateNudgeControl"
        )
        let nudge = RuntimeStateTuning.transformNudge
        return [
            PanelComponents.group([
                PanelComponents.note(
                    "Leave the FormID blank to act on the reference the crosshair targets. "
                        + "Nudge offsets the reference by "
                        + "(\(Self.axisText(nudge.x)), \(Self.axisText(nudge.y)), "
                        + "\(Self.axisText(nudge.z))) world units and accumulates."
                ),
                PanelComponents.labeledFieldRow(
                    caption: "FormID", captionWidth: 60, field: targetControl
                )
            ]),
            PanelComponents.buttonRow([disableControl, enableControl, nudgeControl]),
            statsLabel
        ]
    }

    @objc private func disable() {
        apply("disable") { [provider] target in
            provider?.setReferenceEnabled(false, target: target) ?? false
        }
    }

    @objc private func enable() {
        apply("enable") { [provider] target in
            provider?.setReferenceEnabled(true, target: target) ?? false
        }
    }

    @objc private func nudge() {
        apply("nudge") { [provider] target in
            provider?.nudgeReferenceTransform(target: target) ?? false
        }
    }

    /// Runs one mutation and records what it did, so a failed press reads as a
    /// stated outcome rather than as a button that silently did nothing.
    private func apply(_ verb: String, _ mutate: (RuntimeStateTargetSelector) -> Bool) {
        let target = targetSelector
        let description = Self.describe(target, provider: provider)
        lastActionText = mutate(target)
            ? "Applied \(verb) to \(description)."
            : "No \(verb) applied: \(description)."
        finishInteraction()
    }

    /// Human-readable name of a selector, resolved through the snapshot so the
    /// current-target case reads as the reference rather than as the word
    /// "current".
    static func describe(
        _ target: RuntimeStateTargetSelector,
        provider: (any RuntimeStateControlProviding)?
    ) -> String {
        switch target {
        case .currentTarget:
            provider?.runtimeStateSnapshot.currentTargetDescription ?? "no target"
        case let .formID(text):
            text
        }
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Runtime state: unavailable"
            return
        }
        let current = provider.runtimeStateSnapshot.currentTargetDescription ?? "no target"
        statsLabel.stringValue = "Current target: \(current)\n\(lastActionText)"
    }

    private static func axisText(_ value: Float) -> String {
        String(format: "%.0f", value)
    }
}
