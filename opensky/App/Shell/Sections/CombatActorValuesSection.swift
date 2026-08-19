// World > Combat & Physics > Actor Values section (issue #194, roadmap item
// 15.3, scope point 7; shipped by the M15 gate, issue #198): the health,
// magicka and stamina readouts for the player and the nearest resident actor,
// with the damage and restore controls item 15.3 specified its provider seam
// against.
//
// The target selector is a popup rather than two sets of buttons, because
// "which actor" is one choice a session makes and holds, and duplicating four
// controls per target would be four more ids to record and to keep honest. The
// amount is a text field rather than a slider: a gate that damages an actor by
// exactly 40 has to be able to ask for exactly 40, and a slider's value is a
// float the user cannot type.
//
// Not overridden. A damaged actor is world state, not a panel setting, and a
// "Reset all" that refilled every bar would undo a fight the user started on
// purpose. `ActorValueResetControl` is the deliberate way back, and it acts on
// the selected actor rather than on everything.

import AppKit

final class CombatActorValuesSection: PanelSectionViewController {
    weak var provider: (any ActorValueControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    /// What the amount field starts at: enough to be visible on a bar and far
    /// short of a vanilla actor's health, so the first click damages rather
    /// than kills.
    static let defaultAmount: Float = 10

    /// The two selectors, in popup row order.
    static let targets: [ActorValueTargetSelector] = [.player, .nearestActor]

    let targetControl = NSPopUpButton()
    let kindControl = NSPopUpButton()
    /// Any of the other 161 actor values, typed by vanilla name or by index
    /// (issue #468). Blank means the popup's primary.
    let valueNameControl = NSTextField(string: "")
    let amountControl = NSTextField(string: "10")
    let damageControl = NSButton(title: "Damage", target: nil, action: nil)
    let restoreControl = NSButton(title: "Restore", target: nil, action: nil)
    let setControl = NSButton(title: "Set", target: nil, action: nil)
    let setBaseControl = NSButton(title: "Set base", target: nil, action: nil)
    let refillControl = NSButton(title: "Refill", target: nil, action: nil)
    let resetControl = NSButton(title: "Reset to records", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "CombatActorValuesStatsLabel"
    )

    override var sectionTitle: String {
        "Actor Values"
    }

    override var sectionIdentifier: String {
        "combatActorValues"
    }

    var readout: String {
        statsLabel.stringValue
    }

    /// The amount the two buttons apply, or the default when the field holds
    /// something that is not a number. Never negative: a negative damage is a
    /// restore spelled confusingly, and the section already has a Restore.
    var amount: Float {
        max(0, Float(amountControl.stringValue) ?? Self.defaultAmount)
    }

    /// The primary the popup names.
    var selectedKind: ActorValueKind {
        let kinds = ActorValueKind.allCases
        let index = kindControl.indexOfSelectedItem
        return kinds.indices.contains(index) ? kinds[index] : .health
    }

    /// The actor value the buttons apply to, by vanilla table index.
    ///
    /// The typed name wins when it resolves — by vanilla name, matched the way
    /// `ActorValueIdentity` matches every other name, or by bare index — and
    /// the popup answers otherwise. A field holding something that names no
    /// actor value falls back to the popup rather than acting on a guess, and
    /// the readout's selected-value line is what shows which one won.
    var selectedIndex: Int32 {
        let typed = valueNameControl.stringValue.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty {
            if let index = ActorValueIdentity.index(named: typed) {
                return index
            }
            if let index = Int32(typed), ActorValueIdentity.isVanilla(index: index) {
                return index
            }
        }
        return ActorValueIdentity.storedIndices[selectedKind] ?? 24
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.note(
                "Health, magicka and stamina come from the actor's own record and race "
                    + "derivation; nothing here invents a number. Any of the other 161 actor "
                    + "values — a resistance, a skill, carry weight — is reachable by typing "
                    + "its name or index into Other value, which then wins over the popup. "
                    + "Damage and Restore apply the typed amount to the selected value and "
                    + "Set writes it outright. Set base writes the value's base instead, "
                    + "which for health, magicka or stamina moves the maximum the bar is "
                    + "drawn against — stored as a distance from what the records derive, "
                    + "so Reset to records is still the way back. Refill returns every bar "
                    + "to that maximum, and Reset to records drops the runtime state so the "
                    + "actor derives from its records again. An actor whose health reaches "
                    + "zero dies, which is what the Death & Ragdoll section then shows."
            ),
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Target", captionWidth: 70, field: targetControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Value", captionWidth: 70, field: kindControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Other value", captionWidth: 70, field: valueNameControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Amount", captionWidth: 70, field: amountControl
                ),
                PanelComponents.buttonRow([damageControl, restoreControl, setControl]),
                PanelComponents.buttonRow([setBaseControl, refillControl, resetControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        for control in [
            damageControl, restoreControl, setControl, setBaseControl,
            refillControl, resetControl
        ] {
            control.isEnabled = available
        }
        targetControl.isEnabled = available
        kindControl.isEnabled = available
        valueNameControl.isEnabled = available
        amountControl.isEnabled = available
        guard let provider else { return }
        targetControl.selectItem(
            at: Self.targets.firstIndex(of: provider.actorValueTarget) ?? 0
        )
        provider.actorValueSelection = selectedIndex
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Actor values: unavailable"
            return
        }
        // The selection travels with the read, so the line below describes the
        // value the controls would act on right now rather than the one they
        // acted on last.
        provider.actorValueSelection = selectedIndex
        let snapshot = provider.actorValueControlSnapshot
        statsLabel.stringValue = [
            ActorValueControlReadout.playerText(for: snapshot),
            ActorValueControlReadout.nearestActorText(for: snapshot),
            ActorValueControlReadout.derivationText(for: snapshot),
            ActorValueControlReadout.selectionText(for: snapshot),
            ActorValueControlReadout.controlsText(for: snapshot)
        ].joined(separator: "\n")
    }

    // MARK: - Wiring

    private func configureControls() {
        for target in Self.targets {
            targetControl.addItem(withTitle: target == .player ? "Player" : "Nearest actor")
        }
        PanelComponents.configurePopUp(
            targetControl, target: self, action: #selector(targetChanged),
            identifier: "ActorValueTargetControl"
        )
        for kind in ActorValueKind.allCases {
            kindControl.addItem(withTitle: kind.rawValue.capitalized)
        }
        PanelComponents.configurePopUp(
            kindControl, target: self, action: #selector(kindChanged),
            identifier: "ActorValueKindControl"
        )
        PanelComponents.configureTextField(
            valueNameControl, identifier: "ActorValueNameControl", width: 140
        )
        PanelComponents.configureTextField(
            amountControl, identifier: "ActorValueAmountControl", width: 60
        )
        PanelComponents.configureButton(
            damageControl, target: self, action: #selector(damage),
            identifier: "ActorValueDamageControl"
        )
        PanelComponents.configureButton(
            setControl, target: self, action: #selector(setSelectedValue),
            identifier: "ActorValueSetControl"
        )
        PanelComponents.configureButton(
            setBaseControl, target: self, action: #selector(setSelectedBase),
            identifier: "ActorValueSetBaseControl"
        )
        PanelComponents.configureButton(
            restoreControl, target: self, action: #selector(restore),
            identifier: "ActorValueRestoreControl"
        )
        PanelComponents.configureButton(
            refillControl, target: self, action: #selector(refill),
            identifier: "ActorValueRefillControl"
        )
        PanelComponents.configureButton(
            resetControl, target: self, action: #selector(resetValues),
            identifier: "ActorValueResetControl"
        )
    }

    // MARK: - Actions

    @objc private func targetChanged() {
        let index = targetControl.indexOfSelectedItem
        guard Self.targets.indices.contains(index) else { return }
        provider?.actorValueTarget = Self.targets[index]
        finishInteraction()
    }

    /// The value popup selects what the buttons act on and changes nothing on
    /// its own, so this exists only to give the popup an action and to return
    /// focus to the game view.
    @objc private func kindChanged() {
        finishInteraction()
    }

    @objc private func damage() {
        provider?.actorValueSelection = selectedIndex
        provider?.damageSelectedActor(by: amount)
        finishInteraction()
    }

    @objc private func restore() {
        provider?.actorValueSelection = selectedIndex
        provider?.restoreSelectedActor(by: amount)
        finishInteraction()
    }

    @objc private func setSelectedValue() {
        provider?.actorValueSelection = selectedIndex
        provider?.setSelectedActorValue(to: amount)
        finishInteraction()
    }

    @objc private func setSelectedBase() {
        provider?.actorValueSelection = selectedIndex
        provider?.setSelectedActorBase(to: amount)
        finishInteraction()
    }

    @objc private func refill() {
        provider?.restoreSelectedActorFully()
        finishInteraction()
    }

    @objc private func resetValues() {
        provider?.resetSelectedActorValues()
        finishInteraction()
    }
}
