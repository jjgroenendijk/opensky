// Arrest outcomes: the `PlayerPayCrimeGold` and `SendPlayerToJail` natives
// settle the ledger, the inventory, the clock, and the player's placement.
// See docs/engine/guard-response.md.

import OpenSkyConditions
public import OpenSkyCrimeInterface
public import OpenSkyFormatsESM
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
        let owed = arrest.crime.ledger().entry(for: faction)
        let evidence = arrest.evidenceChest(of: faction).map(world.chestHolder)
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
            showBountyNotice(gold: settlement.bounty, added: false, faction: faction)
            reportArrest(settlement)
            serve(settlement, owed: owed)
        case let .failure(refusal):
            lastGuard = .arrestRefused(faction: factionName(faction), refusal)
        }
        return result
    }

    /// Nil without a ledger or an inventory.
    public func crimeArrest() -> CrimeArrest? {
        guard let runtime = reporter?.runtime, let inventory = world.inventory else { return nil }
        return CrimeArrest(crime: runtime, inventory: inventory)
    }

    /// The guards stood down, and the player either in the jail cell or, without
    /// a cell to enter, through the sentence at once and on the release marker.
    private func serve(_ settlement: ArrestSettlement, owed: CrimeLedgerEntry?) {
        // Before the sentence passes: the cooldown counts from the arrest.
        let now = world.gameSeconds ?? 0
        lastSentenceDays = settlement.sentenceDays
        countArrest(settlement)
        let jailed = imprison(settlement, owed: owed)
        if settlement.sentenceDays > 0, !jailed {
            world.passGameTime(days: settlement.sentenceDays)
            pendingCommands.append(.incrementStat(
                "Days Jailed",
                by: Int32(settlement.sentenceDays)
            ))
        }
        let moved = jailed
            || settlement.releaseMarker.map { world.movePlayer(toMarker: $0) } ?? false
        guards.forgive(settlement.faction)
        // A fine or a sentence does not end the victims' two-day refusal.
        pendingCommands.append(.settlePickpocketCatches(settlement.faction, forgotten: false))
        if case let .confront(guardKey, faction, _) = guards.active, faction == settlement.faction {
            guards.end(settled: true, now: now)
            world.resumePackage(for: guardKey)
        }
        refreshGuardHostility()
        lastGuard = jailed
            ? .jailed(days: settlement.sentenceDays, faction: factionName(settlement.faction))
            : .settled(settlement, faction: factionName(settlement.faction), moved: moved)
    }

    private func countArrest(_ settlement: ArrestSettlement) {
        if settlement.goldPaid > 0 {
            pendingCommands.append(.incrementStat("Fines Paid", by: settlement.goldPaid))
        }
        if settlement.sentenceDays > 0 {
            pendingCommands.append(.incrementStat("Times Jailed", by: 1))
        }
    }

    /// `ARRT`, and `JAIL` when the player serves time. The location is left for
    /// the story manager to fill. `ARRT` names the faction's last crime that cost gold.
    private func reportArrest(_ settlement: ArrestSettlement) {
        guard
            case let .confront(guardKey, faction, _) = guards.active,
            faction == settlement.faction
        else { return }
        storyEvents?.reportArrest(
            by: guardKey, settlement: settlement, crime: reporter?.lastCrimeTypes[faction]
        )
    }
}

extension StoryEventReporting {
    /// `ARRT`, and `JAIL` when the player serves time. Without a known crime, `ARRT`
    /// names theft.
    func reportArrest(
        by guardKey: ReferenceKey, settlement: ArrestSettlement, crime: StoryCrimeType?
    ) {
        reportStoryEvent(.arrest(
            guardActor: guardKey, criminal: .player, location: nil, crime: crime ?? .steal
        ))
        guard settlement.sentenceDays > 0 else { return }
        reportStoryEvent(.jail(
            location: nil, guardActor: guardKey, crimeFaction: settlement.faction,
            gold: settlement.bounty
        ))
    }
}
