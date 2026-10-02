// World > Combat & Physics > Magic Effects section: what acts on the player
// and the nearest resident actor, what the runtime could not apply, and two
// controls to verify a potion without a menu. It sits beside Actor Values,
// because every effect moves an actor value. Not overridden:
// `MagicEffectDispelControl` is the way back.

import AppKit
import OpenSkyMagic

final class CombatMagicEffectsSection: PanelSectionViewController {
    weak var provider: (any MagicEffectControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let consumeControl = NSButton(title: "Consume carried item", target: nil, action: nil)
    let dispelControl = NSButton(title: "Dispel all", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "CombatMagicEffectsStatsLabel"
    )

    override var sectionTitle: String {
        "Magic Effects"
    }

    override var sectionIdentifier: String {
        "combatMagicEffects"
    }

    override func makeContentViews() -> [NSView] {
        consumeControl.toolTip = "Uses the first potion or ingredient the player carries."
        dispelControl.toolTip = "Removes every effect on the player."
        configureControls()
        return [
            PanelComponents.group([
                PanelComponents.buttonRow([consumeControl, dispelControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        consumeControl.isEnabled = available
        dispelControl.isEnabled = available
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Magic effects: unavailable"
            return
        }
        statsLabel.stringValue = MagicEffectControlReadout
            .text(for: provider.magicEffectControlSnapshot)
    }

    // MARK: - Wiring

    private func configureControls() {
        PanelComponents.configureButton(
            consumeControl, target: self, action: #selector(consume),
            identifier: "MagicEffectConsumeControl"
        )
        PanelComponents.configureButton(
            dispelControl, target: self, action: #selector(dispel),
            identifier: "MagicEffectDispelControl"
        )
    }

    // MARK: - Actions

    @objc private func consume() {
        provider?.consumeFirstCarriedMagicItem()
        finishInteraction()
    }

    @objc private func dispel() {
        provider?.dispelPlayerMagicEffects()
        finishInteraction()
    }
}
