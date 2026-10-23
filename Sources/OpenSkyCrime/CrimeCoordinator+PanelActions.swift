// The crime and faction acting half. Every control reaches
// the call a script or the session already makes: a bounty through
// `CrimeRuntime.modifyCrimeGold` (`Faction.ModCrimeGold`), a membership
// through `joinFaction` (`Actor.AddToFaction`), resisting through
// `resistArrest`, and a barter through `openBarter` (`Actor.ShowBarterMenu`).

import OpenSkyFormatsESM
import OpenSkyGameData

extension CrimeCoordinator {
    public var bountyFactionSelection: ReferenceKey? {
        get { panel.bountyFaction }
        set { panel.bountyFaction = newValue }
    }

    public var membershipFactionSelection: ReferenceKey? {
        get { panel.membershipFaction }
        set { panel.membershipFaction = newValue }
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

    @discardableResult
    public func resistArrestWithSelectedFaction() -> CrimeFactionActionOutcome {
        guard reporter != nil else { return notePanel(.unavailable) }
        guard let faction = effectiveBountyFaction else { return notePanel(.noCrimeFaction) }
        resistArrest(with: faction)
        return notePanel(.resisted(lastGuard.text))
    }

    // MARK: - Subject and memberships

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

    // MARK: - Private

    private func subjectName(_ key: ReferenceKey) -> String {
        key == .player ? "The player" : world.actorName(key)
    }

    private func notePanel(_ outcome: CrimeFactionActionOutcome) -> CrimeFactionActionOutcome {
        panel.lastAction = outcome
        return outcome
    }
}
