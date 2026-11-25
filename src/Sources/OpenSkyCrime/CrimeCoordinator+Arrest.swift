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
        ArrestSteps(owner: self).settleArrest(with: faction, outcome)
    }

    /// Nil without a ledger or an inventory.
    public func crimeArrest() -> CrimeArrest? {
        guard let runtime = reporter?.runtime, let inventory = world.inventory else { return nil }
        return CrimeArrest(crime: runtime, inventory: inventory)
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

extension CrimeCoordinator {
    /// Settles an arrest and reports what was paid or served.
    struct ArrestSteps {
        let owner: CrimeCoordinator

        func settleArrest(
            with faction: ReferenceKey,
            _ outcome: ArrestOutcome
        ) -> Result<ArrestSettlement, ArrestRefusal>? {
            let world = owner.world
            guard let arrest = owner.crimeArrest() else { return nil }
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
                if case .pay = outcome {
                    reportFinePaid(settlement)
                }
                owner.showBountyNotice(gold: settlement.bounty, added: false, faction: faction)
                if case let .jail(removeInventory, realJail) = outcome {
                    owner.keepsBelongings = !removeInventory
                    owner.hidesQuestItems = realJail
                }
                reportArrest(settlement)
                serve(settlement, owed: owed)
            case let .failure(refusal):
                owner.lastGuard = .arrestRefused(faction: owner.factionName(faction), refusal)
            }
            return result
        }

        /// The guards stood down, and the player either in the jail cell or, without
        /// a cell to enter, through the sentence at once and on the release marker.
        func serve(_ settlement: ArrestSettlement, owed: CrimeLedgerEntry?) {
            let world = owner.world
            // Before the sentence passes: the cooldown counts from the arrest.
            let now = world.gameSeconds ?? 0
            owner.lastSentenceDays = settlement.sentenceDays
            countArrest(settlement)
            let jailed = owner.imprison(settlement, owed: owed)
            if settlement.sentenceDays > 0, !jailed {
                world.passGameTime(days: settlement.sentenceDays)
                owner.pendingCommands.append(.incrementStat(
                    "Days Jailed",
                    by: Int32(settlement.sentenceDays)
                ))
            }
            let moved = jailed
                || settlement.releaseMarker.map { world.movePlayer(toMarker: $0) } ?? false
            owner.guards.forgive(settlement.faction)
            // A fine or a sentence does not end the victims' two-day refusal.
            owner.pendingCommands.append(.settlePickpocketCatches(
                settlement.faction,
                forgotten: false
            ))
            if
                case let .confront(guardKey, faction, _) = owner.guards.active,
                faction == settlement.faction
            {
                owner.guards.end(settled: true, now: now)
                world.resumePackage(for: guardKey)
            }
            owner.refreshGuardHostility()
            owner.lastGuard = jailed
                ? .jailed(
                    days: settlement.sentenceDays,
                    faction: owner.factionName(settlement.faction)
                )
                : .settled(settlement, faction: owner.factionName(settlement.faction), moved: moved)
        }

        func countArrest(_ settlement: ArrestSettlement) {
            if settlement.goldPaid > 0 {
                owner.pendingCommands.append(.incrementStat("Fines Paid", by: settlement.goldPaid))
            }
            if settlement.sentenceDays > 0 {
                owner.pendingCommands.append(.incrementStat("Times Jailed", by: 1))
            }
        }

        /// `PFIN`, with the guard who confronted the player as `R2`.
        func reportFinePaid(_ settlement: ArrestSettlement) {
            let storyEvents = owner.storyEvents
            var guardKey: ReferenceKey?
            if
                case let .confront(key, faction, _) = owner.guards.active,
                faction == settlement.faction
            {
                guardKey = key
            }
            storyEvents?.reportStoryEvent(.payFine(
                guardActor: guardKey, crimeFaction: settlement.faction, bounty: settlement.bounty
            ))
        }

        /// `ARRT`, and `JAIL` when the player serves time. The location is left for
        /// the story manager to fill. `ARRT` names the faction's last crime that cost gold.
        func reportArrest(_ settlement: ArrestSettlement) {
            let storyEvents = owner.storyEvents
            guard
                case let .confront(guardKey, faction, _) = owner.guards.active,
                faction == settlement.faction
            else { return }
            storyEvents?.reportArrest(
                by: guardKey, settlement: settlement, crime: owner.reporter?.lastCrimeTypes[faction]
            )
        }
    }
}
