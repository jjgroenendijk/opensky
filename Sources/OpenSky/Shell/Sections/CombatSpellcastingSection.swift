// World > Combat & Physics > Spellcasting section: known spells, what each hand
// holds, and the controls from tome to cast. It sits below Magic Effects,
// because a healing cast is read against the magicka and health meters. Not
// overridden: learned spells and readied hands are world state.

import AppKit
import OpenSkyMagic
import OpenSkyMagicInterface

final class CombatSpellcastingSection: PanelSectionViewController {
    weak var provider: (any CastingControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let learnControl = NSButton(title: "Learn start spells", target: nil, action: nil)
    let readTomeControl = NSButton(title: "Read carried tome", target: nil, action: nil)
    let selectControl = NSButton(title: "Next spell", target: nil, action: nil)
    let readyRightControl = NSButton(title: "Ready right", target: nil, action: nil)
    let readyLeftControl = NSButton(title: "Ready left", target: nil, action: nil)
    let castRightControl = NSButton(title: "Cast right", target: nil, action: nil)
    let castLeftControl = NSButton(title: "Cast left", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "CombatSpellcastingStatsLabel"
    )

    override var sectionTitle: String {
        "Spellcasting"
    }

    override var sectionIdentifier: String {
        "combatSpellcasting"
    }

    override func makeContentViews() -> [NSView] {
        learnControl.toolTip = "Teaches Flames, Healing, and the race spells."
        readTomeControl.toolTip = "Reads the first spell tome the player carries."
        castRightControl.toolTip = "Casts one spell. Only self spells cast."
        castLeftControl.toolTip = "Casts one spell. Only self spells cast."
        configureControls()
        return [
            PanelComponents.group([
                PanelComponents.buttonRow([learnControl, readTomeControl, selectControl]),
                PanelComponents.buttonRow([readyRightControl, readyLeftControl]),
                PanelComponents.buttonRow([castRightControl, castLeftControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        for control in [
            learnControl, readTomeControl, selectControl,
            readyRightControl, readyLeftControl, castRightControl, castLeftControl
        ] {
            control.isEnabled = available
        }
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Spellcasting: unavailable"
            return
        }
        statsLabel.stringValue = CastingControlReadout
            .text(for: provider.castingControlSnapshot)
    }

    // MARK: - Wiring

    /// One button's wiring. A named type rather than a tuple because seven
    /// controls is past the strict-lint tuple cap.
    private struct Wiring {
        let control: NSButton
        let action: Selector
        let identifier: String
    }

    private func configureControls() {
        let wiring = [
            Wiring(
                control: learnControl,
                action: #selector(learn),
                identifier: "SpellcastingLearnControl"
            ),
            Wiring(
                control: readTomeControl,
                action: #selector(readTome),
                identifier: "SpellcastingReadTomeControl"
            ),
            Wiring(
                control: selectControl,
                action: #selector(selectNext),
                identifier: "SpellcastingSelectControl"
            ),
            Wiring(
                control: readyRightControl,
                action: #selector(readyRight),
                identifier: "SpellcastingReadyRightControl"
            ),
            Wiring(
                control: readyLeftControl,
                action: #selector(readyLeft),
                identifier: "SpellcastingReadyLeftControl"
            ),
            Wiring(
                control: castRightControl,
                action: #selector(castRight),
                identifier: "SpellcastingCastRightControl"
            ),
            Wiring(
                control: castLeftControl,
                action: #selector(castLeft),
                identifier: "SpellcastingCastLeftControl"
            )
        ]
        for entry in wiring {
            PanelComponents.configureButton(
                entry.control, target: self, action: entry.action,
                identifier: entry.identifier
            )
        }
    }

    // MARK: - Actions

    @objc private func learn() {
        provider?.grantPlayerStartSpells()
        finishInteraction()
    }

    @objc private func readTome() {
        provider?.readFirstCarriedSpellTome()
        finishInteraction()
    }

    @objc private func selectNext() {
        provider?.selectNextKnownSpell()
        finishInteraction()
    }

    @objc private func readyRight() {
        provider?.readySelectedSpell(in: .right)
        finishInteraction()
    }

    @objc private func readyLeft() {
        provider?.readySelectedSpell(in: .left)
        finishInteraction()
    }

    @objc private func castRight() {
        provider?.castReadiedSpell(in: .right)
        finishInteraction()
    }

    @objc private func castLeft() {
        provider?.castReadiedSpell(in: .left)
        finishInteraction()
    }
}
