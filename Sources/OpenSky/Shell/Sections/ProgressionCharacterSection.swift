// World > Progression > Character section: level, experience, perk points, and
// owed attribute picks. The experience award calls `PlayerLevelRuntime.award`,
// the same call a skill point makes. Not overridden.

import AppKit
import OpenSkyGameData
import OpenSkyProgression

final class ProgressionCharacterSection: ProgressionPanelSection {
    /// What the experience field starts at: enough that one click crosses the
    /// first level threshold on the documented curve, so the owed pick the
    /// section is about appears on the first press.
    static let defaultExperience: Float = 500

    let experienceControl = NSTextField(string: "500")
    let awardExperienceControl = NSButton(title: "Award XP", target: nil, action: nil)
    let attributeControl = NSPopUpButton()
    let chooseAttributeControl = NSButton(title: "Choose", target: nil, action: nil)
    let addPerkPointControl = NSButton(title: "Add point", target: nil, action: nil)
    let removePerkPointControl = NSButton(title: "Remove point", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "ProgressionCharacterStatsLabel"
    )

    override var sectionTitle: String {
        "Character"
    }

    override var sectionIdentifier: String {
        "progressionCharacter"
    }

    /// The award the button applies, or the default when the field holds
    /// something that is not a number. Never negative: experience is only ever
    /// banked, and the curve has no way to unspend it.
    var experienceAmount: Float {
        max(0, Float(experienceControl.stringValue) ?? Self.defaultExperience)
    }

    /// The attribute the pick spends on.
    var selectedAttribute: ActorValueKind {
        let kinds = ActorValueKind.allCases
        let index = attributeControl.indexOfSelectedItem
        return kinds.indices.contains(index) ? kinds[index] : .health
    }

    override func makeContentViews() -> [NSView] {
        awardExperienceControl.toolTip =
            "Adds experience and levels up when the threshold is reached."
        chooseAttributeControl.toolTip =
            "Spends one level-up on the attribute and refills the bars."
        configureControls()
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "XP", captionWidth: 70, field: experienceControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Attribute", captionWidth: 70, field: attributeControl
                ),
                PanelComponents.buttonRow([awardExperienceControl, chooseAttributeControl]),
                PanelComponents.buttonRow([addPerkPointControl, removePerkPointControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        for control in [
            awardExperienceControl, chooseAttributeControl,
            addPerkPointControl, removePerkPointControl
        ] {
            control.isEnabled = available
        }
        experienceControl.isEnabled = available
        attributeControl.isEnabled = available
    }

    override func refreshReadout() {
        guard let snapshot = currentSnapshot else {
            statsLabel.stringValue = "Progression: unavailable"
            return
        }
        statsLabel.stringValue = [
            ProgressionControlReadout.characterText(for: snapshot),
            ProgressionControlReadout.picksText(for: snapshot),
            ProgressionControlReadout.controlsText(for: snapshot)
        ].joined(separator: "\n")
    }

    // MARK: - Wiring

    private func configureControls() {
        for kind in ActorValueKind.allCases {
            attributeControl.addItem(withTitle: kind.rawValue.capitalized)
        }
        PanelComponents.configurePopUp(
            attributeControl, target: self, action: #selector(attributeChanged),
            identifier: "ProgressionAttributeControl"
        )
        PanelComponents.configureTextField(
            experienceControl, identifier: "ProgressionExperienceControl", width: 80
        )
        PanelComponents.configureButton(
            awardExperienceControl, target: self, action: #selector(awardExperience),
            identifier: "ProgressionAwardExperienceControl"
        )
        PanelComponents.configureButton(
            chooseAttributeControl, target: self, action: #selector(chooseAttribute),
            identifier: "ProgressionChooseAttributeControl"
        )
        PanelComponents.configureButton(
            addPerkPointControl, target: self, action: #selector(addPerkPoint),
            identifier: "ProgressionAddPerkPointControl"
        )
        PanelComponents.configureButton(
            removePerkPointControl, target: self, action: #selector(removePerkPoint),
            identifier: "ProgressionRemovePerkPointControl"
        )
    }

    // MARK: - Actions

    /// The popup selects what Choose spends on and changes nothing on its own,
    /// so this exists only to give it an action and to return focus to the game
    /// view.
    @objc private func attributeChanged() {
        finishInteraction()
    }

    @objc private func awardExperience() {
        provider?.awardCharacterExperience(experienceAmount)
        finishInteraction()
    }

    @objc private func chooseAttribute() {
        provider?.chooseAttributePick(selectedAttribute)
        finishInteraction()
    }

    @objc private func addPerkPoint() {
        provider?.changePerkPoints(by: 1)
        finishInteraction()
    }

    @objc private func removePerkPoint() {
        provider?.changePerkPoints(by: -1)
        finishInteraction()
    }
}
