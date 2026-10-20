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
    public func modifySelectedBounty(by gold: Int32, violent: Bool) -> CrimeFactionActionOutcome {
        guard let runtime = reporter?.runtime else { return notePanel(.unavailable) }
        guard let faction = effectiveBountyFaction else { return notePanel(.noCrimeFaction) }
        let total = runtime.modifyCrimeGold(by: gold, violent: violent, of: faction)
        refreshGuardHostility()
        return notePanel(.bountyMoved(
            faction: factionName(faction), gold: gold, violent: violent, total: total
        ))
    }

    @discardableResult
    public func clearSelectedBounty() -> CrimeFactionActionOutcome {
        guard let runtime = reporter?.runtime else { return notePanel(.unavailable) }
        guard let faction = effectiveBountyFaction else { return notePanel(.noCrimeFaction) }
        let owed = runtime.clearCrimeGold(of: faction)
        refreshGuardHostility()
        return notePanel(.bountyCleared(faction: factionName(faction), owed: owed))
    }

    /// The same recognition and policy the guard pass uses, then one real
    /// tick of that pass when a world is running.
    @discardableResult
    public func checkGuardConfrontation() -> CrimeFactionActionOutcome {
        guard let runtime = reporter?.runtime else { return notePanel(.unavailable) }
        guard let subject = panel.subject else { return notePanel(.guardCheckNeedsSubject) }
        let name = world.actorName(subject)
        guard
            let profile = world.socialProfile(of: subject),
            let faction = GuardRecognition.policedFaction(
                of: profile, guardFaction: runtime.factions.guardFactionKey
            )
        else { return notePanel(.notAGuard(name)) }
        let bounty = runtime.crimeGold(of: faction)
        let response = CrimeResponsePolicy.response(
            runtime.ledger().entry(for: faction),
            values: runtime.factions.faction(key: faction)?.faction.crimeValues,
            settings: runtime.settings
        )
        var tick: String?
        if world.gameSeconds != nil {
            stepGuardResponse()
            tick = lastGuard.text
        }
        return notePanel(.guardChecked(
            guardName: name, faction: factionName(faction), bounty: bounty,
            response: response, tick: tick
        ))
    }

    @discardableResult
    public func resistArrestWithSelectedFaction() -> CrimeFactionActionOutcome {
        guard reporter != nil else { return notePanel(.unavailable) }
        guard let faction = effectiveBountyFaction else { return notePanel(.noCrimeFaction) }
        resistArrest(with: faction)
        return notePanel(.resisted(lastGuard.text))
    }

    @discardableResult
    public func restockAllVendors() -> CrimeFactionActionOutcome {
        notePanel(.restocked(chests: world.restockAllVendors()))
    }

    @discardableResult
    public func serveJailSentence() -> CrimeFactionActionOutcome {
        guard serveSentence() else { return notePanel(.notInJail) }
        return notePanel(.served(lastGuard.text))
    }

    // MARK: - Subject and memberships

    @discardableResult
    public func selectSocialSubjectFromCrosshair() -> CrimeFactionActionOutcome {
        guard
            let interaction = world.crosshairInteraction,
            let entry = world.references?.referenceEntry(formID: interaction.reference),
            entry.placedActor != nil
        else { return notePanel(.crosshairNotOnActor) }
        panel.subject = entry.key
        return notePanel(.subjectSelected(world.actorName(entry.key)))
    }

    @discardableResult
    public func selectPlayerAsSocialSubject() -> CrimeFactionActionOutcome {
        panel.subject = nil
        return notePanel(.subjectSelected(nil))
    }

    @discardableResult
    public func joinSelectedFaction(rank: Int8) -> CrimeFactionActionOutcome {
        guard world.hasFactionData else { return notePanel(.unavailable) }
        guard let faction = effectiveMembershipFaction else { return notePanel(.noFactions) }
        let key = panel.subject ?? .player
        let changed = world.joinFaction(faction, actor: key, rank: rank)
        return notePanel(.joined(
            actor: subjectName(key), faction: factionName(faction), rank: rank, changed: changed
        ))
    }

    @discardableResult
    public func leaveSelectedFaction() -> CrimeFactionActionOutcome {
        guard world.hasFactionData else { return notePanel(.unavailable) }
        guard let faction = effectiveMembershipFaction else { return notePanel(.noFactions) }
        let key = panel.subject ?? .player
        return notePanel(.left(
            actor: subjectName(key),
            faction: factionName(faction),
            changed: world.leaveFaction(faction, actor: key)
        ))
    }

    // MARK: - Vendor

    @discardableResult
    public func barterWithSocialSubject() -> CrimeFactionActionOutcome {
        notePanel(.barter(world.openBarter(
            with: panel.subject ?? .player,
            vendorFaction: panel.vendorOverride
        )))
    }

    // MARK: - Private

    private func subjectName(_ key: ReferenceKey) -> String {
        key == .player ? "The player" : world.actorName(key)
    }

    private func notePanel(_ outcome: CrimeFactionActionOutcome) -> CrimeFactionActionOutcome {
        panel.lastAction = outcome
        return outcome
    }
}
