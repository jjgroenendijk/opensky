// World > Progression > Character section (issue #500, roadmap item 20.7): the
// player's level, the experience under it, the perk points it paid for, and the
// attribute pick each level still owes.
//
// The experience award is a control rather than only a readout because the
// alternative way to reach a level-up is to swing a sword a few hundred times.
// It drives `PlayerLevelRuntime.award`, which is the same call a skill point
// makes on the player's behalf, so what the button demonstrates is the real
// curve rather than a shortcut around it.
//
// Not overridden. A level, a perk point and a spent pick are world state the
// user produced on purpose, not panel settings, and a "Reset all" that took a
// level back would undo the demonstration rather than a knob.

import AppKit

final class ProgressionCharacterSection: PanelSectionViewController {
    weak var provider: (any ProgressionControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

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

    var readout: String {
        statsLabel.stringValue
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
        configureControls()
        return [
            PanelComponents.note(
                "Level, banked character experience and unspent perk points come from the "
                    + "player's own progress component; nothing here invents a number. "
                    + "Award XP banks the typed amount against the level curve, which is "
                    + "the same call a skill point makes, and raises the level the moment "
                    + "the threshold is crossed. Each level gained owes one attribute "
                    + "pick: Choose spends it on health, magicka or stamina, adding the "
                    + "level-up points as a base offset and refilling all three bars — a "
                    + "stamina pick also raises carry weight. Add point and Remove point "
                    + "are Game.ModPerkPoints, for reaching a tree without leveling first."
            ),
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
        guard let provider else {
            statsLabel.stringValue = "Progression: unavailable"
            return
        }
        let snapshot = provider.progressionControlSnapshot
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
