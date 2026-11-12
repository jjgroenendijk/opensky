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
        ) { CrimeConditionResolution(crime: self, owning: references) }
    }
}

/// The seam, built from the coordinator's state. Only the player's ledger travels.
extension CrimeConditionResolution {
    @MainActor
    init(crime: CrimeCoordinator, owning references: [ReferenceKey]) {
        guard let reporter = crime.reporter else {
            self = .empty
            return
        }
        let ledger = reporter.runtime.ledger()
        self.init(
            factions: reporter.runtime.factions,
            sourcePlugin: crime.pluginName,
            currentCrimeFaction: crime.crimeFaction(in: crime.world.currentCellLocation),
            ledgers: ledger.isEmpty ? [:] : [.player: ledger],
            situation: Self.situation(of: crime, ledger: ledger, references: references)
        )
    }

    @MainActor
    private static func situation(
        of crime: CrimeCoordinator, ledger: CrimeLedgerState, references: [ReferenceKey]
    ) -> CrimeSituation {
        var alarmed = Set(crime.pursuitTargets.keys)
        var arresting: ReferenceKey?
        if case let .confront(guardKey, _, _) = crime.guards.active {
            alarmed.insert(guardKey)
            arresting = guardKey
        }
        let payable = ledger.entries.map(\.faction).filter { crime.canPayCrimeGold(to: $0) == true }
        var owners: [ReferenceKey: ReferenceOwner] = [:]
        for key in references {
            owners[key] = crime.crimeOwner(of: key)
        }
        return CrimeSituation(
            guardFaction: crime.reporter?.runtime.factions.guardFactionKey,
            victims: crime.assaultedActors.union(crime.murders.keys),
            trespassers: crime.isPlayerTrespassing ? [.player] : [],
            alarmed: alarmed,
            arrestingGuard: arresting,
            payableFactions: Set(payable),
            lastSentenceDays: crime.lastSentenceDays,
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
