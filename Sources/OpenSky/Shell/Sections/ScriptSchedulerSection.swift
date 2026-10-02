// World > Scripts > Scheduler section: the Papyrus VM transport. Pause freezes
// the VM tick; the step buttons run fixed steps, to walk a `Utility.Wait` or a
// `RegisterForUpdate` timer one edge at a time. A paused VM is this
// destination's override. The pause never writes `Renderer.worldSimPaused`,
// which belongs to menu mode.

import AppKit
import OpenSkyScripting

final class ScriptSchedulerSection: PanelSectionViewController {
    /// Ticks the burst button applies. Twenty fixed steps is two thirds of a
    /// second of VM time at the 1/30 s step: long enough to carry a short
    /// `Utility.Wait` to its resume, short enough to stay one observable jump.
    static let burstTicks = 20

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
    /// the sidebar dot. A paused VM is the deviation; stepping is a momentary
    /// action that leaves no setting behind.
    static func isOverridden(provider: (any ScriptControlProviding)?) -> Bool {
        provider?.scriptsSnapshot.isPaused ?? false
    }

    /// The destination's reset: let the VM run again.
    static func resetToDefaults(provider: (any ScriptControlProviding)?) {
        provider?.setScriptsPaused(false)
    }

    override func makeContentViews() -> [NSView] {
        pauseControl.toolTip = "Pauses scripts only. The world keeps running."
        configureControls()
        return [
            PanelComponents.group([pauseControl]),
            PanelComponents.buttonRow([stepControl, burstControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        pauseControl.state = provider?.scriptsSnapshot.isPaused == true ? .on : .off
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Papyrus: unavailable"
            return
        }
        statsLabel.stringValue = ScriptsReadout.schedulerText(for: provider.scriptsSnapshot)
    }
}
