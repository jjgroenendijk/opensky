// World > Combat & Physics > Spellcasting section (issue #470, roadmap item
// 19.7): what the player knows, what each hand is holding, and the seven
// controls that take a spell from a tome to a cast without leaving the panel.
//
// It sits directly below Magic Effects because that is where a cast lands: the
// acceptance picture for this item is a healing spell moving the magicka meter
// down and the health meter up, and all three readouts are read together.
//
// Not overridden. A learned spell and a readied hand are world state, not panel
// settings, and a "Reset all" that forgot the player's spells would undo
// something the user did on purpose.

import AppKit

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

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.note(
                "Learn start spells grants Flames and Healing — the two UESP documents the "
                    + "player as always knowing — plus the spell list the player's race "
                    + "authors, once character generation names one. Read carried tome opens "
                    + "the first spell tome in the inventory, which teaches its spell and "
                    + "marks the book read; the tome is not consumed. Next "
                    + "spell moves the selection the two Ready buttons act on; readying a "
                    + "spell takes the hands its EQUP slot names and unequips whatever held "
                    + "them. Cast runs one whole cast without holding a button — in walk mode "
                    + "the attack button casts with the right hand and the block button with "
                    + "the left, whenever that hand holds a spell. Only self-delivery spells "
                    + "cast; anything aimed is counted on the coverage line."
            ),
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
