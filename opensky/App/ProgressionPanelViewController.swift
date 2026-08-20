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
            for section in progressionSections {
                section.provider = provider
            }
        }
    }

    /// One ticker for the whole panel, because all three sections read the same
    /// snapshot and it is expensive to build — see `refreshSections`.
    override var sectionsTickIndependently: Bool {
        false
    }

    override func makeSections() -> [PanelSectionViewController] {
        progressionSections
    }

    /// Builds the tick's snapshot once and hands the same value to all three
    /// sections (issue #556).
    ///
    /// The hand-down is cleared afterwards rather than left standing: a refresh
    /// outside this fan-out — what a button press triggers — has to read the
    /// provider live, because the action it follows just changed what the
    /// provider would say.
    override func refreshSections() {
        let snapshot = provider?.progressionControlSnapshot
        for section in progressionSections {
            section.tickSnapshot = snapshot
        }
        defer {
            for section in progressionSections {
                section.tickSnapshot = nil
            }
        }
        super.refreshSections()
    }

    /// The panel's sections in display order, typed as the base every one of
    /// them shares so the snapshot hand-down can reach them.
    var progressionSections: [ProgressionPanelSection] {
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
