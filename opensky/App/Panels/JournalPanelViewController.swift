// World > Quests & Journal destination panel (issue #184): the sidebar
// verification surface for quest state and the vanilla journal page. Thin
// composition of self-contained sections on the shared panel framework, the
// same shape as ScriptsPanelViewController. Exact sidebar path and control ids:
// docs/engine/journal.md.
//
// Section order follows the order a session reaches for them: what the quests
// are doing, then how to drive one by hand, then what the movie made of it.
//
// It is a destination of its own rather than sections under World > Scripts
// because quest *state* is not a script fact: a quest runs, reaches stages and
// shows objectives whether or not it carries a single line of Papyrus, and
// World > Scripts > Quests deliberately counts only the script side.

import AppKit

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
