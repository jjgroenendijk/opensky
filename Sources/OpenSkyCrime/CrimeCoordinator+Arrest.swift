// Arrest outcomes: the `PlayerPayCrimeGold` and `SendPlayerToJail` natives
// settle the ledger, the inventory, the clock, and the player's placement.
// See docs/engine/guard-response.md.

import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension CrimeCoordinator: CrimeArrestSession {
    public func canPayCrimeGold(to faction: ReferenceKey) -> Bool? {
        crimeArrest()?.canPay(faction)
    }

    public func settleArrest(
        with faction: ReferenceKey,
        _ outcome: ArrestOutcome
    ) -> Result<ArrestSettlement, ArrestRefusal>? {
        guard let arrest = crimeArrest() else { return nil }
        let evidence = evidenceHolder(of: faction, arrest: arrest)
        let result: Result<ArrestSettlement, ArrestRefusal> = switch outcome {
        case let .pay(removeStolen, goToJail):
            Result { () throws(ArrestRefusal) in
                try arrest.pay(
                    faction, removeStolen: removeStolen, goToJail: goToJail, evidence: evidence
                )
            }
        case .jail:
            Result { () throws(ArrestRefusal) in try arrest.jail(faction, evidence: evidence) }
        }
        switch result {
        case let .success(settlement):
            reportArrest(settlement)
            serve(settlement)
        case let .failure(refusal):
            lastGuardText = "Arrest with \(factionName(faction)) refused: \(refusal)."
        }
        return result
    }

    /// Nil without a ledger or an inventory.
    public func crimeArrest() -> CrimeArrest? {
        guard let runtime = reporter?.runtime, let inventory = world?.inventory else { return nil }
        return CrimeArrest(crime: runtime, inventory: inventory)
    }

    /// The resident chest when it is streamed in, so its own `CNTO` baseline
    /// is kept, and a baseline-free holder under the same key otherwise.
    private func evidenceHolder(of faction: ReferenceKey, arrest: CrimeArrest) -> InventoryHolder? {
        guard let key = arrest.evidenceChest(of: faction) else { return nil }
        if let placed = world?.references?.referenceEntry(key: key)?.placedReference {
            return InventoryHolder(
                key: key,
                owner: .container(base: placed.base),
                cell: world?.references?.cellLocation(of: key)
            )
        }
        return arrest.unresidentEvidence(of: faction)
    }

    /// The sentence on the clock, the player at the release marker when it is
    /// resident, and the guards stood down. A marker that is not resident is
    /// left alone: there is no cross-cell teleport yet.
    private func serve(_ settlement: ArrestSettlement) {
        // Before the sentence passes: the cooldown counts from the arrest.
        let now = world?.gameSeconds ?? 0
        if settlement.sentenceDays > 0 {
            world?.passGameTime(days: settlement.sentenceDays)
        }
        let moved = settlement.releaseMarker.map { world?.movePlayer(toMarker: $0) ?? false }
            ?? false
        guards.forgive(settlement.faction)
        if case let .confront(guardKey, faction, _) = guards.active, faction == settlement.faction {
            guards.end(settled: true, now: now)
            world?.resumePackage(for: guardKey)
        }
        refreshGuardHostility()
        lastGuardText = CrimeCore.settlementText(
            settlement, factionName: factionName(settlement.faction), moved: moved
        )
    }

    /// `ARRT`, and `JAIL` when the player serves time. The location is left for
    /// the story manager to fill. `ARRT` names no crime type yet.
    private func reportArrest(_ settlement: ArrestSettlement) {
        guard
            case let .confront(guardKey, faction, _) = guards.active,
            faction == settlement.faction
        else { return }
        storyEvents?.reportStoryEvent(.arrest(
            guardActor: guardKey, criminal: .player, location: nil, crime: .steal
        ))
        guard settlement.sentenceDays > 0 else { return }
        storyEvents?.reportStoryEvent(.jail(
            location: nil, guardActor: guardKey, crimeFaction: faction, gold: settlement.bounty
        ))
    }
}
