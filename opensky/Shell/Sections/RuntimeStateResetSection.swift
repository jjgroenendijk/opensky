// World > Runtime State > Reset section (M10.1.5): drops runtime deltas, either
// for the selected reference or for the whole store.
//
// This is the section that carries the destination's overridden-ness. A dirty
// reference is exactly the "differs from the documented default" condition the
// sidebar's override indicator describes — plugin data is the default — and
// "Reset all" is the operation that restores it, so the destination-level reset
// in `DestinationRegistry` maps straight onto `resetAllReferenceState()`. The
// other three sections report false so a fresh session reads as not overridden.

import AppKit

final class RuntimeStateResetSection: PanelSectionViewController {
    weak var provider: (any RuntimeStateControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    /// Reads the FormID field the Change section owns, so both sections act on
    /// one reference. Wired by the panel; nil means "current target".
    var targetSelectorSource: (() -> RuntimeStateTargetSelector)?

    let resetTargetControl = NSButton(title: "Reset target", target: nil, action: nil)
    let resetAllControl = NSButton(title: "Reset all", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "RuntimeStateResetStatsLabel")
    private var lastActionText = "No reset applied yet."

    override var sectionTitle: String {
        "Reset"
    }

    override var sectionIdentifier: String {
        "runtimeStateReset"
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

    static func isOverridden(provider: (any RuntimeStateControlProviding)?) -> Bool {
        (provider?.runtimeStateSnapshot.dirtyReferenceCount ?? 0) > 0
    }

    static func resetToDefaults(provider: (any RuntimeStateControlProviding)?) {
        provider?.resetAllReferenceState()
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureButton(
            resetTargetControl, target: self, action: #selector(resetTarget),
            identifier: "RuntimeStateResetTargetControl"
        )
        PanelComponents.configureButton(
            resetAllControl, target: self, action: #selector(resetAll),
            identifier: "RuntimeStateResetAllControl"
        )
        return [
            PanelComponents.note(
                "Reset target uses the FormID from the Change section. Reset all restores "
                    + "every reference to plugin data and is what the sidebar's Reset "
                    + "control runs."
            ),
            PanelComponents.buttonRow([resetTargetControl, resetAllControl]),
            statsLabel
        ]
    }

    @objc private func resetTarget() {
        let target = targetSelectorSource?() ?? .currentTarget
        let description = RuntimeStateChangeSection.describe(target, provider: provider)
        lastActionText = provider?.resetReferenceState(target: target) == true
            ? "Reset \(description)."
            : "Nothing to reset for \(description)."
        finishInteraction()
    }

    @objc private func resetAll() {
        provider?.resetAllReferenceState()
        lastActionText = "Reset every reference to plugin data."
        finishInteraction()
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Runtime state: unavailable"
            return
        }
        let dirty = provider.runtimeStateSnapshot.dirtyReferenceCount
        statsLabel.stringValue = "Dirty references: \(dirty)\n\(lastActionText)"
    }
}
