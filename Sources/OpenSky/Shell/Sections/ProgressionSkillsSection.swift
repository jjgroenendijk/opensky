// World > Progression > Skills section: the eighteen skills with their level,
// trained level and progress. Grant use is `Game.AdvanceSkill` through the
// skill's AVIF curve; grant point is `Game.IncrementSkill`, like a trainer.
// The skill popup shares the provider selection with the Perk Tree section.
// Not overridden.

import AppKit
import OpenSkyProgression

final class ProgressionSkillsSection: ProgressionPanelSection {
    /// What the amount field starts at: one use, which is what a single swing
    /// reports, so the first click shows the smallest real advance rather than
    /// a level.
    static let defaultAmount: Float = 1

    let skillControl = NSPopUpButton()
    let amountControl = NSTextField(string: "1")
    let advanceControl = NSButton(title: "Grant use", target: nil, action: nil)
    let incrementControl = NSButton(title: "Grant point", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "ProgressionSkillsStatsLabel"
    )
    /// The popup's rows, in the order the snapshot lists them.
    private var options: [SkillProgressReadout] = []

    override var sectionTitle: String {
        "Skills"
    }

    override var sectionIdentifier: String {
        "progressionSkills"
    }

    /// The use amount the button applies, or the default when the field holds
    /// something that is not a number. Never negative: a skill is never
    /// un-used, and the runtime counts a non-positive amount as a drop.
    var useAmount: Float {
        max(0, Float(amountControl.stringValue) ?? Self.defaultAmount)
    }

    override func makeContentViews() -> [NSView] {
        advanceControl.toolTip = "Adds skill use, like a swing or a cast."
        incrementControl.toolTip = "Raises the skill by one point, like a trainer."
        configureControls()
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Skill", captionWidth: 70, field: skillControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Use", captionWidth: 70, field: amountControl
                ),
                PanelComponents.buttonRow([advanceControl, incrementControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        advanceControl.isEnabled = available
        incrementControl.isEnabled = available
        amountControl.isEnabled = available
        skillControl.isEnabled = available
        reloadOptions()
    }

    override func refreshReadout() {
        guard let snapshot = currentSnapshot else {
            statsLabel.stringValue = "Skills: unavailable"
            return
        }
        reloadOptions(snapshot: snapshot)
        statsLabel.stringValue = ProgressionControlReadout.skillsText(for: snapshot)
    }

    // MARK: - Wiring

    private func configureControls() {
        PanelComponents.configurePopUp(
            skillControl, target: self, action: #selector(skillChanged),
            identifier: "ProgressionSkillControl", width: 160
        )
        PanelComponents.configureTextField(
            amountControl, identifier: "ProgressionSkillAmountControl", width: 60
        )
        PanelComponents.configureButton(
            advanceControl, target: self, action: #selector(advance),
            identifier: "ProgressionAdvanceSkillControl"
        )
        PanelComponents.configureButton(
            incrementControl, target: self, action: #selector(increment),
            identifier: "ProgressionIncrementSkillControl"
        )
    }

    /// Rebuilds the popup only when its membership changes. The rows carry
    /// names alone: a row that also carried the level would be rewritten twice
    /// a second and would close the menu in the user's hand.
    private func reloadOptions(snapshot: ProgressionControlSnapshot? = nil) {
        guard let snapshot = snapshot ?? currentSnapshot else {
            options = []
            skillControl.removeAllItems()
            skillControl.isEnabled = false
            return
        }
        skillControl.isEnabled = !snapshot.skills.isEmpty
        guard snapshot.skills.map(\.name) != options.map(\.name) else {
            options = snapshot.skills
            selectCurrentSkill(snapshot)
            return
        }
        options = snapshot.skills
        skillControl.removeAllItems()
        skillControl.addItems(withTitles: options.map(\.name))
        selectCurrentSkill(snapshot)
    }

    private func selectCurrentSkill(_ snapshot: ProgressionControlSnapshot) {
        guard
            let index = options.firstIndex(where: { $0.index == snapshot.selectedSkill })
        else { return }
        skillControl.selectItem(at: index)
    }

    // MARK: - Actions

    @objc private func skillChanged() {
        let index = skillControl.indexOfSelectedItem
        guard options.indices.contains(index) else { return }
        provider?.progressionSkillSelection = options[index].index
        finishInteraction()
    }

    @objc private func advance() {
        provider?.advanceSelectedSkill(byUse: useAmount)
        finishInteraction()
    }

    @objc private func increment() {
        provider?.incrementSelectedSkill()
        finishInteraction()
    }
}
