// The crime seam of the condition context. See docs/engine/condition-functions-world.md#crime.

import OpenSkyConditions
public import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState

/// What the crime seam was built from: the coordinator's own state, the store kinds
/// it reads, where the player stands, and the run-ons asked about.
extension CrimeCoordinator {
    /// Only the player's ledger travels: nothing gives an NPC a bounty, so a
    /// whole table would be a per-frame walk for rows that are all empty.
    /// `references` are the run-ons whose owner `IsOwner` may ask about.
    public func conditionResolution(owning references: [ReferenceKey] = [])
        -> CrimeConditionResolution
    {
        guard let reporter else { return .empty }
        return conditionCache.value(
            revisions: (conditionRevision, scriptedOwnerRevision?()), runtime: reporter.runtime,
            scope: (world.currentCellLocation, references)
        ) { freshConditionResolution(owning: references) }
    }

    func freshConditionResolution(owning references: [ReferenceKey]) -> CrimeConditionResolution {
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

/// The crime condition seam, built again only when something it reads changed.
final class CrimeConditionCache {
    private let cache = RevisionCache<CrimeConditionKey, CrimeConditionResolution>()

    /// The ledger, the gold that pays it, and faction memberships.
    private static let kinds: [WorldStateComponentKind] = [.crimeLedger, .inventory, .factions]

    /// `revisions` are the coordinator's own and the scripted owners'; `scope` is the
    /// player's cell and the references `IsOwner` may ask about.
    func value(
        revisions: (coordinator: UInt64, scriptedOwners: UInt64?), runtime: CrimeRuntime,
        scope: (cell: CellSceneLocation?, references: [ReferenceKey]),
        build: () -> CrimeConditionResolution
    ) -> CrimeConditionResolution {
        let key = CrimeConditionKey(
            coordinator: revisions.coordinator,
            store: runtime.revision(of: Self.kinds),
            scriptedOwners: revisions.scriptedOwners,
            cell: scope.cell,
            references: scope.references
        )
        return cache.value(for: key, build: build)
    }
}

struct CrimeConditionKey: Hashable {
    let coordinator: UInt64
    let store: UInt64
    let scriptedOwners: UInt64?
    let cell: CellSceneLocation?
    let references: [ReferenceKey]
}
