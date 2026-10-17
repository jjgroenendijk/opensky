// The crime seam of the condition context. See docs/engine/condition-functions-world.md#crime.

import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData

extension CrimeCoordinator {
    /// Only the player's ledger travels: nothing gives an NPC a bounty, so a
    /// whole table would be a per-frame walk for rows that are all empty.
    /// `references` are the run-ons whose owner `IsOwner` may ask about.
    public func conditionResolution(owning references: [ReferenceKey] = [])
        -> CrimeConditionResolution
    {
        guard let reporter else { return .empty }
        let ledger = reporter.runtime.ledger()
        return CrimeConditionResolution(
            factions: reporter.runtime.factions,
            sourcePlugin: pluginName,
            currentCrimeFaction: crimeFaction(in: world.currentCellLocation),
            ledgers: ledger.isEmpty ? [:] : [.player: ledger],
            situation: situation(ledger: ledger, references: references)
        )
    }

    private func situation(ledger: CrimeLedgerState, references: [ReferenceKey]) -> CrimeSituation {
        var alarmed = Set(pursuitTargets.keys)
        var arresting: ReferenceKey?
        if case let .confront(guardKey, _, _) = guards.active {
            alarmed.insert(guardKey)
            arresting = guardKey
        }
        let payable = ledger.entries.map(\.faction).filter { canPayCrimeGold(to: $0) == true }
        var owners: [ReferenceKey: ReferenceOwner] = [:]
        for key in references {
            owners[key] = crimeOwner(of: key)
        }
        return CrimeSituation(
            guardFaction: reporter?.runtime.factions.guardFactionKey,
            victims: assaultedActors.union(murders.keys),
            trespassers: isPlayerTrespassing ? [.player] : [],
            alarmed: alarmed,
            arrestingGuard: arresting,
            payableFactions: Set(payable),
            lastSentenceDays: lastSentenceDays,
            owners: owners
        )
    }
}
