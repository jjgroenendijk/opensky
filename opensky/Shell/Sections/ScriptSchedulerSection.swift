// World > Scripts > Scheduler section (issue #278): the transport for the
// Papyrus VM. Pause freezes the VM's own tick, and the two step buttons run
// fixed steps by hand so a latent `Utility.Wait` or a `RegisterForUpdate` timer
// can be walked through one edge at a time.
//
// This is the section that carries the destination's overridden-ness: a paused
// VM is the one thing under World > Scripts that sits away from its documented
// default, and the sidebar's reset resumes it. The other three sections are
// read-only and report false.
//
// The VM pause is deliberately not the engine's menu-mode world pause. Those
// are separate freezes with separate controls, and this one never writes
// `Renderer.worldSimPaused`.
//
// Control wiring and the `@objc` actions live in the satellite
// `ScriptSchedulerSectionInput.swift`, the same split `SWFRuntimeSection` uses.

import AppKit

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
        configureControls()
        return [
            PanelComponents.note(
                "Pause freezes the Papyrus VM only; the world keeps simulating and the "
                    + "menu-mode pause stays separate. A paused VM accumulates no time, so "
                    + "resuming never replays the pause as catch-up steps. Step runs fixed "
                    + "steps immediately, whether or not the VM is paused."
            ),
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
