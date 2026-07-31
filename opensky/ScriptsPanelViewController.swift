// World > Scripts destination panel (issue #278): the sidebar verification
// surface for the Papyrus VM. Thin composition of self-contained sections on
// the shared panel framework, the same shape as RuntimeStatePanelViewController.
// Exact sidebar path and control ids: docs/engine/papyrus-vm.md.
//
// Section order follows the order a session reaches for them: what is loaded,
// then what it did, then how to drive it by hand, then what it could not do.
//
// It is a destination of its own rather than sections under World > Runtime
// State because the VM is a distinct subsystem with its own transport: pausing
// and stepping scripts is not the same freeze as menu mode, and confusing the
// two is exactly what a separate path prevents.

import AppKit

final class ScriptsPanelViewController: InspectorPanelViewController {
    let instancesSection = ScriptInstancesSection()
    let eventsSection = ScriptEventsSection()
    let schedulerSection = ScriptSchedulerSection()
    let nativeTallySection = ScriptNativeTallySection()

    /// Live Papyrus bridge. Weak: the game controller owns this panel's parent
    /// and the VM, so the panel must not retain back.
    weak var provider: (any ScriptControlProviding)? {
        didSet {
            instancesSection.provider = provider
            eventsSection.provider = provider
            schedulerSection.provider = provider
            nativeTallySection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [instancesSection, eventsSection, schedulerSection, nativeTallySection]
    }

    /// Control forwards for the verification-surface tests, mirroring
    /// RuntimeStatePanelViewController's convention.
    var scriptPauseControl: NSButton {
        schedulerSection.pauseControl
    }

    var scriptStepControl: NSButton {
        schedulerSection.stepControl
    }

    var scriptBurstControl: NSButton {
        schedulerSection.burstControl
    }
}
