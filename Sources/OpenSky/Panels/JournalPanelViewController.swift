// World > Quests & Journal: quest state and the vanilla journal page
// (docs/engine/journal.md). It is not under World > Scripts because a quest
// runs and shows objectives whether or not it has any Papyrus.

import AppKit
import OpenSkyMenus

final class JournalPanelViewController: InspectorPanelViewController {
    let questsSection = JournalQuestsSection()
    let controlsSection = JournalQuestControlsSection()
    let pageSection = JournalPageSection()

    /// Live journal bridge. Weak: the game controller owns this panel's parent
    /// and the quest runtime, so the panel must not retain back.
    weak var provider: (any JournalControlProviding)? {
        didSet {
            questsSection.provider = provider
            controlsSection.provider = provider
            pageSection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [questsSection, controlsSection, pageSection]
    }

    /// Control forwards for the verification-surface tests, mirroring
    /// ScriptsPanelViewController's convention.
    var questControl: NSComboBox {
        questsSection.questControl
    }

    var startControl: NSButton {
        controlsSection.startControl
    }

    var stopControl: NSButton {
        controlsSection.stopControl
    }

    var stageControl: NSTextField {
        controlsSection.stageControl
    }

    var setStageControl: NSButton {
        controlsSection.setStageControl
    }

    var openControl: NSButton {
        pageSection.openControl
    }

    var closeControl: NSButton {
        pageSection.closeControl
    }
}
