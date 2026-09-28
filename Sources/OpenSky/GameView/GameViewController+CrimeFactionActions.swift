// The `World > Crime & Factions` panel's acting half (issue #507, roadmap item
// 21.8). Every control reaches the call a script or the session already makes:
// a bounty moves through `CrimeRuntime.modifyCrimeGold`, which is
// `Faction.ModCrimeGold`'s door; a membership through `joinFaction`, which is
// `Actor.AddToFaction`'s; resisting through `resistArrest`, which a closed
// arrest conversation also takes; and a barter through `openBarter`, which is
// where `Actor.ShowBarterMenu` lands.

import AppKit
import OpenSkyEngine
import OpenSkyFormats
import OpenSkyGameData

extension GameViewController: CrimeFactionControlProviding {
    var bountyFactionSelection: ReferenceKey? {
        get { crime.panel.bountyFaction }
        set { crime.panel.bountyFaction = newValue }
    }

    var membershipFactionSelection: ReferenceKey? {
        get { crime.panel.membershipFaction }
        set { crime.panel.membershipFaction = newValue }
    }

    var vendorOverrideSelection: ReferenceKey? {
        get { crime.panel.vendorOverride }
        set { crime.panel.vendorOverride = newValue }
    }

    // MARK: - Bounty

    @discardableResult
    func modifySelectedBounty(by gold: Int32, violent: Bool) -> String {
        guard let runtime = crime.reporter?.runtime else { return unavailableCrimePanel() }
        guard let faction = effectiveBountyFaction else {
            return notePanel("No faction in this load order tracks crime.")
        }
        let total = runtime.modifyCrimeGold(by: gold, violent: violent, of: faction)
        refreshGuardHostility(ledger: runtime.ledger())
        let half = violent ? "violent" : "non-violent"
        return notePanel("Moved the \(half) bounty with \(crimeFactionName(faction)) by "
            + "\(gold): now \(total) gold.")
    }

    @discardableResult
    func clearSelectedBounty() -> String {
        guard let runtime = crime.reporter?.runtime else { return unavailableCrimePanel() }
        guard let faction = effectiveBountyFaction else {
            return notePanel("No faction in this load order tracks crime.")
        }
        let owed = runtime.clearCrimeGold(of: faction)
        refreshGuardHostility(ledger: runtime.ledger())
        return notePanel("Cleared \(owed) gold owed to \(crimeFactionName(faction)).")
    }

    /// What the subject would do about the player's bounty, from the same
    /// recognition and policy the guard pass uses, then one real tick of that
    /// pass when a world is running — which is where a detecting guard walks
    /// up or turns hostile.
    @discardableResult
    func checkGuardConfrontation() -> String {
        guard let runtime = crime.reporter?.runtime else { return unavailableCrimePanel() }
        guard let subject = crime.panel.subject else {
            return notePanel("Guard check: pick an actor with the crosshair first — "
                + "the player is nobody's guard.")
        }
        let name = dialogueSpeakerLabel(for: subject)
        guard
            let profile = socialProfile(of: subject),
            let faction = GuardRecognition.policedFaction(
                of: profile, guardFaction: runtime.factions.guardFactionKey
            )
        else { return notePanel("Guard check: \(name) is not a guard.") }
        let bounty = runtime.crimeGold(of: faction)
        let response = CrimeResponsePolicy.response(
            bounty: bounty,
            values: runtime.factions.faction(key: faction)?.faction.crimeValues
        )
        var text = "Guard check: \(name) polices \(crimeFactionName(faction)); bounty "
            + "\(bounty) gold → \(CrimeFactionReadout.responseText(response))."
        if renderer != nil {
            advanceGuardResponse()
            text += " Guard tick: \(crime.lastGuardText)"
        } else {
            text += " No world is running, so no guard tick ran."
        }
        return notePanel(text)
    }

    @discardableResult
    func resistArrestWithSelectedFaction() -> String {
        guard crime.reporter != nil else { return unavailableCrimePanel() }
        guard let faction = effectiveBountyFaction else {
            return notePanel("No faction in this load order tracks crime.")
        }
        resistArrest(with: faction)
        return notePanel(crime.lastGuardText)
    }

    // MARK: - Subject and memberships

    @discardableResult
    func selectSocialSubjectFromCrosshair() -> String {
        guard
            let interaction = currentInteraction,
            let entry = streamer?.referenceEntry(formID: interaction.reference),
            entry.placedActor != nil
        else { return notePanel("The crosshair is not on an actor.") }
        crime.panel.subject = entry.key
        return notePanel("Subject: \(dialogueSpeakerLabel(for: entry.key)).")
    }

    @discardableResult
    func selectPlayerAsSocialSubject() -> String {
        crime.panel.subject = nil
        return notePanel("Subject: the player.")
    }

    @discardableResult
    func joinSelectedFaction(rank: Int8) -> String {
        guard factions.runtime != nil else { return unavailableCrimePanel() }
        guard let faction = effectiveMembershipFaction else {
            return notePanel("This load order carries no factions.")
        }
        let key = crime.panel.subject ?? .player
        let changed = joinFaction(faction, actor: key, rank: rank)
        let who = subjectName(key)
        let name = crimeFactionName(faction)
        return notePanel(changed
            ? "\(who) is in \(name) at rank \(rank)."
            : "\(who) was already in \(name) at rank \(rank), or is not resident.")
    }

    @discardableResult
    func leaveSelectedFaction() -> String {
        guard factions.runtime != nil else { return unavailableCrimePanel() }
        guard let faction = effectiveMembershipFaction else {
            return notePanel("This load order carries no factions.")
        }
        let key = crime.panel.subject ?? .player
        let who = subjectName(key)
        let name = crimeFactionName(faction)
        return notePanel(leaveFaction(faction, actor: key)
            ? "\(who) left \(name)."
            : "\(who) was not in \(name).")
    }

    // MARK: - Vendor

    @discardableResult
    func barterWithSocialSubject() -> String {
        notePanel(openBarter(
            with: crime.panel.subject ?? .player,
            vendorFaction: crime.panel.vendorOverride
        ))
    }

    // MARK: - Private

    private func subjectName(_ key: ReferenceKey) -> String {
        key == .player ? "The player" : dialogueSpeakerLabel(for: key)
    }

    private func unavailableCrimePanel() -> String {
        notePanel(CrimeFactionControlSnapshot.unavailable.lastActionText)
    }

    private func notePanel(_ text: String) -> String {
        crime.panel.lastActionText = text
        return text
    }
}
