// World > Progression destination panel (issue #500, roadmap item 20.7): the
// sidebar verification surface for the whole M20 character sheet, composed from
// the three sections items 20.1 through 20.6 built the runtime for.
//
// A destination of its own rather than more sections under `World > Combat &
// Physics`, which is where the actor-value controls live. Three sections, their
// own sub-navigation — a skill selects a tree and a box selects a record — and
// fifteen controls are past the promotion threshold in docs/tools/app-ui.md,
// and the M20 acceptance names this path top-level, which outranks the
// threshold anyway. Combat is about what an actor is worth right now;
// progression is about what the player has become, which is a different
// question about a different subject.
//
// Section order follows the order progression happens in: the character the
// levels land on, the skills that earn them, and the perks they buy.

import AppKit

final class ProgressionPanelViewController: InspectorPanelViewController {
    let characterSection = ProgressionCharacterSection()
    let skillsSection = ProgressionSkillsSection()
    let perkTreeSection = ProgressionPerkTreeSection()

    /// Weak, for the reason every other panel holds its providers weakly: the
    /// game controller owns this panel's parent, so the panel must not retain
    /// back.
    weak var provider: (any ProgressionControlProviding)? {
        didSet {
            characterSection.provider = provider
            skillsSection.provider = provider
            perkTreeSection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [characterSection, skillsSection, perkTreeSection]
    }

    /// Control forwards for the verification-surface tests, mirroring
    /// CombatPhysicsPanelViewController's convention.
    var awardExperienceControl: NSButton {
        characterSection.awardExperienceControl
    }

    var chooseAttributeControl: NSButton {
        characterSection.chooseAttributeControl
    }

    var advanceSkillControl: NSButton {
        skillsSection.advanceControl
    }

    var incrementSkillControl: NSButton {
        skillsSection.incrementControl
    }

    var spendPerkPointControl: NSButton {
        perkTreeSection.spendControl
    }

    var grantPerkControl: NSButton {
        perkTreeSection.grantControl
    }

    var removePerkControl: NSButton {
        perkTreeSection.removeControl
    }
}
