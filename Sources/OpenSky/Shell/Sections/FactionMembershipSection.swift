// World > Crime & Factions > Memberships: the player's and a picked actor's
// factions and ranks, what that actor makes of the player with each hostility
// term, and whether it is a guard. The actor is picked with the crosshair. Not
// overridden: a membership is world state.

import AppKit
import OpenSkyCrime

final class FactionMembershipSection: CrimeFactionPanelSection {
    let crosshairControl = NSButton(title: "Use crosshair actor", target: nil, action: nil)
    let playerControl = NSButton(title: "Use player", target: nil, action: nil)
    let factionControl = NSPopUpButton()
    let rankControl = NSTextField(string: "0")
    let joinControl = NSButton(title: "Join / set rank", target: nil, action: nil)
    let leaveControl = NSButton(title: "Leave", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "FactionMembershipStatsLabel"
    )
    private var options: [FactionOption] = []

    override var sectionTitle: String {
        "Memberships"
    }

    override var sectionIdentifier: String {
        "factionMembership"
    }

    var readout: String {
        statsLabel.stringValue
    }

    /// The typed rank, clamped into what a membership stores; 0 for anything
    /// that is not a number.
    var rank: Int8 {
        let typed = Int(rankControl.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        return Int8(clamping: typed)
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.note(
                "Faction memberships and ranks for the player and for the subject — the "
                    + "actor last picked with the crosshair. The reaction line is the "
                    + "derivation the combat loop asks, with each term of its precedence "
                    + "list beneath it: the stored override, crime, the relationship rank, "
                    + "then the interfaction relation. Join puts the subject in the chosen "
                    + "faction at the typed rank, or moves it there; Leave takes it out."
            ),
            PanelComponents.group([
                PanelComponents.buttonRow([crosshairControl, playerControl]),
                PanelComponents.labeledFieldRow(
                    caption: "Faction", captionWidth: 60, field: factionControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Rank", captionWidth: 60, field: rankControl
                ),
                PanelComponents.buttonRow([joinControl, leaveControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = currentSnapshot?.isAvailable == true
        for control in [crosshairControl, playerControl, joinControl, leaveControl] {
            control.isEnabled = available
        }
        rankControl.isEnabled = available
        syncFactions()
    }

    override func refreshReadout() {
        guard let snapshot = currentSnapshot else {
            statsLabel.stringValue = "Factions: unavailable"
            return
        }
        syncFactions(snapshot)
        statsLabel.stringValue = CrimeFactionReadout.membershipText(for: snapshot)
    }

    private func syncFactions(_ snapshot: CrimeFactionControlSnapshot? = nil) {
        let snapshot = snapshot ?? currentSnapshot
        options = sync(
            factionControl,
            options: snapshot?.factions ?? [],
            shown: options,
            selected: snapshot?.selectedFaction
        )
    }

    private func configureControls() {
        PanelComponents.configureButton(
            crosshairControl, target: self, action: #selector(useCrosshair),
            identifier: "FactionSubjectCrosshairControl"
        )
        PanelComponents.configureButton(
            playerControl, target: self, action: #selector(usePlayer),
            identifier: "FactionSubjectPlayerControl"
        )
        PanelComponents.configurePopUp(
            factionControl, target: self, action: #selector(factionChanged),
            identifier: "FactionSelectControl", width: 200
        )
        PanelComponents.configureTextField(
            rankControl, identifier: "FactionRankControl", width: 60
        )
        PanelComponents.configureButton(
            joinControl, target: self, action: #selector(join),
            identifier: "FactionJoinControl"
        )
        PanelComponents.configureButton(
            leaveControl, target: self, action: #selector(leave),
            identifier: "FactionLeaveControl"
        )
    }

    // MARK: - Actions

    @objc private func useCrosshair() {
        provider?.selectSocialSubjectFromCrosshair()
        finishInteraction()
    }

    @objc private func usePlayer() {
        provider?.selectPlayerAsSocialSubject()
        finishInteraction()
    }

    @objc private func factionChanged() {
        provider?.membershipFactionSelection =
            selectedOption(of: factionControl, in: options)?.key
        finishInteraction()
    }

    @objc private func join() {
        provider?.joinSelectedFaction(rank: rank)
        finishInteraction()
    }

    @objc private func leave() {
        provider?.leaveSelectedFaction()
        finishInteraction()
    }
}
