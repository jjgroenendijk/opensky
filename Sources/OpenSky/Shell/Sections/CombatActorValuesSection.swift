// World > Combat & Physics > Actor Values section: health, magicka and stamina
// for the player and the nearest resident actor, with damage and restore
// controls. The amount is a text field so a test can ask for exactly 40. Not
// overridden: a damaged actor is world state, so "Reset all" leaves it alone;
// `ActorValueResetControl` resets the selected actor.

import AppKit
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

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
    /// Any of the other 161 actor values, typed by vanilla name or by index.
    /// Blank means the popup's primary.
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

    /// The actor value the buttons apply to, by vanilla table index. A typed
    /// name or index wins when it resolves; otherwise the popup answers. The
    /// readout's selected-value line shows which one won.
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
        valueNameControl.toolTip = "Any actor value by name or index. Overrides the popup."
        setBaseControl.toolTip =
            "Sets the base value. For health, magicka, or stamina this moves the maximum."
        refillControl.toolTip = "Fills every bar to its maximum."
        resetControl.toolTip = "Drops runtime changes so the actor reads its records again."
        configureControls()
        return [
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
