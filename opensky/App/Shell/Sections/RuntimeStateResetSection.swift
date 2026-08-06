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

    /// Destination-level overridden-ness, which `DestinationRegistry` reads for
    /// the sidebar dot: the union of everything under World > Runtime State
    /// that can sit away from plugin data. It lives on this section because
    /// this is the section whose reset is the destination's reset.
    static func isOverridden(provider: (any RuntimeStateControlProviding)?) -> Bool {
        guard let provider else { return false }
        return provider.runtimeStateSnapshot.dirtyReferenceCount > 0
            || RuntimeStateGlobalsSection.isOverridden(provider: provider)
            || RuntimeStateTimeSection.isOverridden(provider: provider)
    }

    /// The destination's Reset all: every reference delta, every global
    /// override, and the timescale back to the vanilla default.
    static func resetToDefaults(provider: (any RuntimeStateControlProviding)?) {
        provider?.resetAllReferenceState()
        RuntimeStateGlobalsSection.resetToDefaults(provider: provider)
        RuntimeStateTimeSection.resetToDefaults(provider: provider)
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
                    + "every reference and every global to plugin data and puts the "
                    + "timescale back to its vanilla value; it is what the sidebar's Reset "
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
        Self.resetToDefaults(provider: provider)
        lastActionText = "Reset every reference and global to plugin data."
        finishInteraction()
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Runtime state: unavailable"
            return
        }
        let snapshot = provider.runtimeStateSnapshot
        statsLabel.stringValue = "Dirty references: \(snapshot.dirtyReferenceCount)"
            + "  Overridden globals: \(snapshot.overriddenGlobalCount)\n\(lastActionText)"
    }
}
