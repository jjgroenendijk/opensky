// World > Crime & Factions > Bounty (issue #507): the player's ledger per crime
// faction, the crime faction answering for the cell the player stands in, and
// the controls that move a bounty or put a guard to the test.
//
// Not overridden. A bounty is world state — the save carries it, a script reads
// it — and a "Reset all" that paid it off would undo the thing the section
// exists to demonstrate rather than restore a knob.

import AppKit
import OpenSkyEngine
import OpenSkyFormatsCore

final class CrimeBountySection: CrimeFactionPanelSection {
    static let defaultAmount: Int32 = 100

    let factionControl = NSPopUpButton()
    let amountControl = NSTextField(string: "100")
    let violentControl = NSButton(checkboxWithTitle: "Violent", target: nil, action: nil)
    let addControl = NSButton(title: "Add", target: nil, action: nil)
    let clearControl = NSButton(title: "Clear", target: nil, action: nil)
    let guardCheckControl = NSButton(title: "Guard check", target: nil, action: nil)
    let resistControl = NSButton(title: "Resist arrest", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "CrimeBountyStatsLabel")
    private var options: [FactionOption] = []

    override var sectionTitle: String {
        "Bounty"
    }

    override var sectionIdentifier: String {
        "crimeBounty"
    }

    var readout: String {
        statsLabel.stringValue
    }

    /// The typed gold, or the default when the field holds no number. Negative
    /// is allowed: `Faction.ModCrimeGold` takes one, and the ledger clamps at 0.
    var amount: Int32 {
        Int32(amountControl.stringValue.trimmingCharacters(in: .whitespaces))
            ?? Self.defaultAmount
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.note(
                "Crime gold the player owes each crime faction, split into the "
                    + "non-violent and violent halves Faction.ModCrimeGold writes, and "
                    + "what that faction's guards do about it. Add moves the chosen half "
                    + "by the typed gold (negative pays it down); Clear drops both. "
                    + "Guard check asks the actor picked under Memberships what it would "
                    + "do, then runs one tick of the guard pass. Resist arrest turns the "
                    + "chosen faction's guards hostile, as walking out of the arrest "
                    + "conversation does."
            ),
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Faction", captionWidth: 60, field: factionControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Gold", captionWidth: 60, field: amountControl
                ),
                violentControl,
                PanelComponents.buttonRow([addControl, clearControl]),
                PanelComponents.buttonRow([guardCheckControl, resistControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = currentSnapshot?.isAvailable == true
        for control in [addControl, clearControl, guardCheckControl, resistControl] {
            control.isEnabled = available
        }
        amountControl.isEnabled = available
        violentControl.isEnabled = available
        syncFactions()
    }

    override func refreshReadout() {
        guard let snapshot = currentSnapshot else {
            statsLabel.stringValue = "Crime: unavailable"
            return
        }
        syncFactions(snapshot)
        statsLabel.stringValue = CrimeFactionReadout.bountyText(for: snapshot)
    }

    private func syncFactions(_ snapshot: CrimeFactionControlSnapshot? = nil) {
        let snapshot = snapshot ?? currentSnapshot
        options = sync(
            factionControl,
            options: snapshot?.crimeFactions ?? [],
            shown: options,
            selected: snapshot?.selectedCrimeFaction
        )
    }

    private func configureControls() {
        PanelComponents.configurePopUp(
            factionControl, target: self, action: #selector(factionChanged),
            identifier: "CrimeBountyFactionControl", width: 200
        )
        PanelComponents.configureTextField(
            amountControl, identifier: "CrimeBountyAmountControl", width: 80
        )
        PanelComponents.configureCheckbox(
            violentControl, target: self, action: #selector(violentChanged),
            identifier: "CrimeBountyViolentControl"
        )
        PanelComponents.configureButton(
            addControl, target: self, action: #selector(addBounty),
            identifier: "CrimeBountyAddControl"
        )
        PanelComponents.configureButton(
            clearControl, target: self, action: #selector(clearBounty),
            identifier: "CrimeBountyClearControl"
        )
        PanelComponents.configureButton(
            guardCheckControl, target: self, action: #selector(checkGuard),
            identifier: "CrimeGuardCheckControl"
        )
        PanelComponents.configureButton(
            resistControl, target: self, action: #selector(resistArrest),
            identifier: "CrimeResistArrestControl"
        )
    }

    // MARK: - Actions

    @objc private func factionChanged() {
        provider?.bountyFactionSelection = selectedOption(of: factionControl, in: options)?.key
        finishInteraction()
    }

    /// The checkbox chooses which half Add moves and changes nothing on its own.
    @objc private func violentChanged() {
        finishInteraction()
    }

    @objc private func addBounty() {
        provider?.modifySelectedBounty(by: amount, violent: violentControl.state == .on)
        finishInteraction()
    }

    @objc private func clearBounty() {
        provider?.clearSelectedBounty()
        finishInteraction()
    }

    @objc private func checkGuard() {
        provider?.checkGuardConfrontation()
        finishInteraction()
    }

    @objc private func resistArrest() {
        provider?.resistArrestWithSelectedFaction()
        finishInteraction()
    }
}
