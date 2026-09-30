// World > AI & Navigation > Package section: which package the selected
// actor's schedule chose, its procedure, and a force-reevaluate button. There
// is no direct package control, because the schedule and conditions decide.
// Scrub the clock under World > Runtime State > Time, then reevaluate. Not
// overridden.

import AppKit
import OpenSkyWorld

final class AIPackageSection: PanelSectionViewController {
    weak var provider: (any AINavigationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let reevaluateControl = NSButton(title: "Reevaluate now", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "AIPackageStatsLabel")

    override var sectionTitle: String {
        "Package"
    }

    override var sectionIdentifier: String {
        "aiPackage"
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureButton(
            reevaluateControl, target: self, action: #selector(reevaluate),
            identifier: "AIPackageReevaluateControl"
        )
        return [
            PanelComponents.note(
                "An actor's packages come from its own record and the factions and templates "
                    + "behind it, highest priority first; the first one whose schedule matches "
                    + "the game clock and whose conditions pass is the one it runs. Selection "
                    + "is re-checked on schedule boundaries and at most every fifteen game "
                    + "minutes, so scrub the clock under World > Runtime State > Time and "
                    + "press Reevaluate to see the choice change without waiting."
            ),
            PanelComponents.buttonRow([reevaluateControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        reevaluateControl.isEnabled = provider != nil
    }

    override func refreshReadout() {
        guard let snapshot = provider?.aiNavigationSnapshot else {
            statsLabel.stringValue = "Package: unavailable"
            return
        }
        statsLabel.stringValue = AIPackageReadout.packageText(for: snapshot)
    }

    // MARK: - Actions

    @objc private func reevaluate() {
        provider?.reevaluateSelectedAIActorPackage()
        finishInteraction()
    }
}
