// The `World > Crime & Factions` panel's acting half. Every control reaches
// the call a script or the session already makes: a bounty through
// `CrimeRuntime.modifyCrimeGold` (`Faction.ModCrimeGold`), a membership
// through `joinFaction` (`Actor.AddToFaction`), resisting through
// `resistArrest`, and a barter through `openBarter` (`Actor.ShowBarterMenu`).

import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldState

extension CrimeCoordinator: CrimeFactionControlProviding {
    public var bountyFactionSelection: ReferenceKey? {
        get { panel.bountyFaction }
        set { panel.bountyFaction = newValue }
    }

    public var membershipFactionSelection: ReferenceKey? {
        get { panel.membershipFaction }
        set { panel.membershipFaction = newValue }
    }

    public var vendorOverrideSelection: ReferenceKey? {
        get { panel.vendorOverride }
        set { panel.vendorOverride = newValue }
    }

    // MARK: - Bounty

    @discardableResult
    public func modifySelectedBounty(by gold: Int32, violent: Bool) -> String {
        guard let runtime = reporter?.runtime else { return notePanelUnavailable() }
        guard let faction = effectiveBountyFaction else {
            return notePanel(CrimeCore.noFactionTracksCrimeText)
        }
        let total = runtime.modifyCrimeGold(by: gold, violent: violent, of: faction)
        refreshGuardHostility()
        let half = violent ? "violent" : "non-violent"
        return notePanel("Moved the \(half) bounty with \(factionName(faction)) by "
            + "\(gold): now \(total) gold.")
    }

    @discardableResult
    public func clearSelectedBounty() -> String {
        guard let runtime = reporter?.runtime else { return notePanelUnavailable() }
        guard let faction = effectiveBountyFaction else {
            return notePanel(CrimeCore.noFactionTracksCrimeText)
        }
        let owed = runtime.clearCrimeGold(of: faction)
        refreshGuardHostility()
        return notePanel("Cleared \(owed) gold owed to \(factionName(faction)).")
    }

    /// The same recognition and policy the guard pass uses, then one real
    /// tick of that pass when a world is running.
    @discardableResult
    public func checkGuardConfrontation() -> String {
        guard let runtime = reporter?.runtime else { return notePanelUnavailable() }
        guard let subject = panel.subject else {
            return notePanel("Guard check: pick an actor with the crosshair first — "
                + "the player is nobody's guard.")
        }
        let name = world?.actorName(subject) ?? subject.description
        guard
            let profile = world?.socialProfile(of: subject),
            let faction = GuardRecognition.policedFaction(
                of: profile, guardFaction: runtime.factions.guardFactionKey
            )
        else { return notePanel("Guard check: \(name) is not a guard.") }
        let bounty = runtime.crimeGold(of: faction)
        let response = CrimeResponsePolicy.response(
            bounty: bounty,
            values: runtime.factions.faction(key: faction)?.faction.crimeValues
        )
        var text = "Guard check: \(name) polices \(factionName(faction)); bounty "
            + "\(bounty) gold → \(CrimeFactionReadout.responseText(response))."
        if world?.gameSeconds != nil {
            advanceGuardResponse()
            text += " Guard tick: \(lastGuardText)"
        } else {
            text += " No world is running, so no guard tick ran."
        }
        return notePanel(text)
    }

    @discardableResult
    public func resistArrestWithSelectedFaction() -> String {
        guard reporter != nil else { return notePanelUnavailable() }
        guard let faction = effectiveBountyFaction else {
            return notePanel(CrimeCore.noFactionTracksCrimeText)
        }
        resistArrest(with: faction)
        return notePanel(lastGuardText)
    }

    // MARK: - Subject and memberships

    @discardableResult
    public func selectSocialSubjectFromCrosshair() -> String {
        guard
            let interaction = world?.crosshairInteraction,
            let entry = world?.references?.referenceEntry(formID: interaction.reference),
            entry.placedActor != nil
        else { return notePanel("The crosshair is not on an actor.") }
        panel.subject = entry.key
        return notePanel("Subject: \(world?.actorName(entry.key) ?? entry.key.description).")
    }

    @discardableResult
    public func selectPlayerAsSocialSubject() -> String {
        panel.subject = nil
        return notePanel("Subject: the player.")
    }

    @discardableResult
    public func joinSelectedFaction(rank: Int8) -> String {
        guard let world, world.hasFactionData else { return notePanelUnavailable() }
        guard let faction = effectiveMembershipFaction else {
            return notePanel(CrimeCore.noFactionsText)
        }
        let key = panel.subject ?? .player
        let changed = world.joinFaction(faction, actor: key, rank: rank)
        let who = subjectName(key)
        let name = factionName(faction)
        return notePanel(changed
            ? "\(who) is in \(name) at rank \(rank)."
            : "\(who) was already in \(name) at rank \(rank), or is not resident.")
    }

    @discardableResult
    public func leaveSelectedFaction() -> String {
        guard let world, world.hasFactionData else { return notePanelUnavailable() }
        guard let faction = effectiveMembershipFaction else {
            return notePanel(CrimeCore.noFactionsText)
        }
        let key = panel.subject ?? .player
        let who = subjectName(key)
        let name = factionName(faction)
        return notePanel(world.leaveFaction(faction, actor: key)
            ? "\(who) left \(name)."
            : "\(who) was not in \(name).")
    }

    // MARK: - Vendor

    @discardableResult
    public func barterWithSocialSubject() -> String {
        notePanel(world?.openBarter(
            with: panel.subject ?? .player,
            vendorFaction: panel.vendorOverride
        ) ?? CrimeFactionControlSnapshot.unavailable.lastActionText)
    }

    // MARK: - Private

    private func subjectName(_ key: ReferenceKey) -> String {
        key == .player ? "The player" : world?.actorName(key) ?? key.description
    }

    private func notePanelUnavailable() -> String {
        notePanel(CrimeFactionControlSnapshot.unavailable.lastActionText)
    }

    private func notePanel(_ text: String) -> String {
        panel.lastActionText = text
        return text
    }
}
