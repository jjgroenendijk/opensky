// World > Scripts > Scheduler section: the Papyrus VM transport. Pause freezes
// the VM tick; the step buttons run fixed steps, to walk a `Utility.Wait` or a
// `RegisterForUpdate` timer one edge at a time. A paused VM is this
// destination's override. The pause never writes `Renderer.worldSimPaused`,
// which belongs to menu mode.

import AppKit
import OpenSkyScripting
import OpenSkyScriptingInterface

final class ScriptSchedulerSection: PanelSectionViewController {
    /// Ticks the burst button applies. Twenty fixed steps is two thirds of a
    /// second of VM time at the 1/30 s step: long enough to carry a short
    /// `Utility.Wait` to its resume, short enough to stay one observable jump.
    static let burstTicks = 20
    /// Instructions per fixed step the budget control offers. The standard budget is one.
    static let budgetChoices = [1000, 2000, 4000, 8000, 16000, 100_000]

    weak var provider: (any ScriptControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let pauseControl = NSButton(checkboxWithTitle: "Pause VM", target: nil, action: nil)
    let stepControl = NSButton(title: "Step", target: nil, action: nil)
    let burstControl = NSButton(
        title: "Step x\(ScriptSchedulerSection.burstTicks)", target: nil, action: nil
    )
    let budgetControl = NSPopUpButton()

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "ScriptSchedulerStatsLabel"
    )

    override var sectionTitle: String {
        "Scheduler"
    }

    override var sectionIdentifier: String {
        "scriptScheduler"
    }

    /// Current readout text; the verification-surface tests read it directly.
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
    /// the sidebar dot. A paused VM or a changed budget is the deviation; stepping
    /// is a momentary action that leaves no setting behind. A session without a VM
    /// reports a zero budget, which is no deviation.
    static func isOverridden(provider: (any ScriptControlProviding)?) -> Bool {
        guard let snapshot = provider?.scriptsSnapshot else { return false }
        let budget = snapshot.budgetInstructions
        return snapshot.isPaused
            || (budget != 0 && budget != PapyrusTickBudget.standard.instructions)
    }

    /// The destination's reset: let the VM run again, with the standard budget.
    static func resetToDefaults(provider: (any ScriptControlProviding)?) {
        provider?.setScriptsPaused(false)
        provider?.setScriptInstructionBudget(PapyrusTickBudget.standard.instructions)
    }

    override func makeContentViews() -> [NSView] {
        pauseControl.toolTip = "Pauses scripts only. The world keeps running."
        budgetControl.toolTip = "Instructions all scripts may run per step together."
        configureControls()
        return [
            PanelComponents.group([pauseControl]),
            PanelComponents.buttonRow([stepControl, burstControl]),
            PanelComponents.labeledFieldRow(
                caption: "Step budget", captionWidth: 90, field: budgetControl
            ),
            statsLabel
        ]
    }

    override func syncControls() {
        let snapshot = provider?.scriptsSnapshot
        pauseControl.state = snapshot?.isPaused == true ? .on : .off
        budgetControl.selectItem(withTag: snapshot?.budgetInstructions ?? 0)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Papyrus: unavailable"
            return
        }
        statsLabel.stringValue = ScriptsReadout.schedulerText(for: provider.scriptsSnapshot)
    }
}
