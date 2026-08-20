// World > Progression > Skills section (issue #500, roadmap item 20.7): the
// eighteen skills with what each reads, what it was trained to, and how far its
// next point is — plus the two ways a skill moves.
//
// Grant use is `Game.AdvanceSkill`'s unit and the one every swing, shot and
// cast reports in: the amount is converted by the skill's own AVIF parameters,
// so what the button demonstrates is the real curve. Grant point is
// `Game.IncrementSkill`, which is what a trainer or a skill book does — it
// leaves the accumulated experience alone, because the point did not come from
// use.
//
// The skill popup writes the provider's shared selection, so the Perk Tree
// section below follows it and the two sections cannot describe different
// skills.
//
// Not overridden: a trained skill is world state, not a panel setting.

import AppKit

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

    var readout: String {
        statsLabel.stringValue
    }

    /// The use amount the button applies, or the default when the field holds
    /// something that is not a number. Never negative: a skill is never
    /// un-used, and the runtime counts a non-positive amount as a drop.
    var useAmount: Float {
        max(0, Float(amountControl.stringValue) ?? Self.defaultAmount)
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.note(
                "Every skill line reads its live value, the trained base advancement "
                    + "compares against, the experience banked in its Skill Advance slot, "
                    + "and what the next point costs from there. Grant use reports the "
                    + "typed amount of use on the selected skill, exactly as a swing, a "
                    + "shot or a cast does, and the skill's own AVIF parameters convert "
                    + "it. Grant point raises the skill by a whole point instead, which "
                    + "is what a trainer does, and leaves the banked experience alone. "
                    + "Either way the point banks character experience, so a few grants "
                    + "level the character above."
            ),
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
