// World > Scripts destination panel for the Papyrus VM (docs/engine/papyrus-world.md).
// Sections run in the order a session needs them: what is loaded, what it did,
// how to drive it, what it could not do. A separate destination, because
// pausing scripts is a different freeze from menu mode.

import AppKit
import OpenSkyScripting

final class ScriptsPanelViewController: InspectorPanelViewController {
    let instancesSection = ScriptInstancesSection()
    let questsSection = ScriptQuestsSection()
    let eventsSection = ScriptEventsSection()
    let schedulerSection = ScriptSchedulerSection()
    let nativeTallySection = ScriptNativeTallySection()

    /// Live Papyrus bridge. Weak: the game controller owns this panel's parent
    /// and the VM, so the panel must not retain back.
    weak var provider: (any ScriptControlProviding)? {
        didSet {
            instancesSection.provider = provider
            questsSection.provider = provider
            eventsSection.provider = provider
            schedulerSection.provider = provider
            nativeTallySection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [instancesSection, questsSection, eventsSection, schedulerSection, nativeTallySection]
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

    var scriptBudgetControl: NSPopUpButton {
        schedulerSection.budgetControl
    }
}
