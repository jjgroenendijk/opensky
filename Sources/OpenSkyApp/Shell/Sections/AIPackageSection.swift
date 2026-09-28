// World > AI & Navigation > Package section (issue #201, roadmap item 16.5;
// shipped by the M16 gate, issue #203): which package the selected actor's
// schedule chose, what procedure it runs, and the force-reevaluate the runtime
// exposes.
//
// One button. Selection is otherwise driven by the game clock and by the
// conditions the package stack carries, and a panel that could set a package
// directly would be showing a state the schedule never produced. Reevaluate is
// the honest control: scrub the clock under `World > Runtime State > Time`,
// press this, and read which package the same rules pick now.
//
// Not overridden. A package selection is world state driven by a clock, not a
// panel setting.

import AppKit

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

    var readout: String {
        statsLabel.stringValue
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
