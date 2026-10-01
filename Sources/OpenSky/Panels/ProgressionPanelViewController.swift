// World > Progression: the character sheet. It is its own destination because
// it is about what the player has become, not what an actor is worth in a
// fight. Sections follow progression: character, skills, perks.

import AppKit
import OpenSkyProgression

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

    /// Builds the tick's snapshot once for all three sections. The hand-down is
    /// cleared afterwards, because a refresh after a button press must read the
    /// provider live.
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
