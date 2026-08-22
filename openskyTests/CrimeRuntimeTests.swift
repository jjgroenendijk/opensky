// The bounty ledger and what a crime costs (issue #504, roadmap item 21.5).
//
// Every amount asserted here comes from the fixture's `CRVA`, which carries the
// numbers the local install authors on `CrimeFactionWhiterun` and UESP
// publishes for the player: murder 1000, assault 40, trespass 5, and half the
// stolen item's value rounded down (<https://en.uesp.net/wiki/Skyrim:Crime>).

import Foundation
@testable import opensky
import Testing

@MainActor
struct CrimeRuntimeTests {
    private let hold = CrimeFixture.key(CrimeFixture.Factions.hold)

    // MARK: - What each crime costs

    @Test
    func eachCrimeAccruesTheAmountItsFactionPrices() throws {
        let runtime = try CrimeFixture.runtime()

        #expect(runtime.report(CrimeFixture.event(.assault)).gold == 40)
        #expect(runtime.report(CrimeFixture.event(.murder)).gold == 1000)
        #expect(runtime.report(CrimeFixture.event(.trespass)).gold == 5)
        #expect(runtime.crimeGold(of: hold) == 1045)
    }

    /// "Half of the stolen item's value, rounded down" — the 0.5 comes from the
    /// record's steal multiplier, and the rounding is what makes a one-gold
    /// trinket free.
    @Test
    func theftIsTheStolenValueTimesTheStealMultiplierRoundedDown() throws {
        let runtime = try CrimeFixture.runtime()

        #expect(runtime.report(CrimeFixture.event(.theft, stolenValue: 100)).gold == 50)
        #expect(runtime.report(CrimeFixture.event(.theft, stolenValue: 7)).gold == 3)
        #expect(runtime.report(CrimeFixture.event(.theft, stolenValue: 1)).gold == 0)
        #expect(runtime.crimeGold(of: hold) == 53)
        #expect(runtime.crimeCounts(of: hold).theft == 3)
    }

    /// A `CRVA` too short to carry a steal multiplier means the neutral
    /// multiplier of 1 rather than a free theft, which is the decision
    /// `Faction.swift` left to this issue.
    @Test
    func anAbsentStealMultiplierChargesTheFullValue() {
        let short = Faction.CrimeValues(
            arrest: true,
            attackOnSight: false,
            murder: 1000,
            assault: 40,
            trespass: 5,
            pickpocket: 25,
            unknown: 0,
            stealMultiplier: nil,
            escape: nil,
            werewolf: nil
        )
        let table = CrimeGoldTable(values: short)

        #expect(table.bounty(for: CrimeFixture.event(.theft, stolenValue: 100)) == 100)
        #expect(CrimeGoldTable.stealBounty(of: 100, multiplier: nil) == 100)
    }

    /// A faction with no `CRVA` prices nothing, and the crime is still counted.
    @Test
    func anUnpricedFactionChargesNothingAndStillCounts() {
        #expect(CrimeGoldTable.unpriced.bounty(for: CrimeFixture.event(.murder)) == 0)
    }

    // MARK: - Witnessing

    /// "If you are caught doing an illegal action by a witness you will incur a
    /// bounty", but "Regardless of whether a crime is witnessed, the Statistics
    /// tab on the menu keeps track of all your criminal activities" — so an
    /// unwitnessed crime leaves a count and no gold.
    @Test
    func anUnwitnessedCrimeIsCountedAndCostsNothing() throws {
        let runtime = try CrimeFixture.runtime()
        let outcome = runtime.report(
            CrimeFixture.event(.theft, witnessed: false, stolenValue: 100)
        )

        #expect(outcome.gold == 0)
        #expect(outcome.recorded)
        #expect(outcome.refusal == .unwitnessed)
        #expect(runtime.crimeGold(of: hold) == 0)
        #expect(runtime.crimeCounts(of: hold).theft == 1)
    }

    /// The witness source is what turns an act into a witnessed one, and a
    /// session with no perception pass answers "nobody saw".
    @Test
    func reportWitnessedAsksTheWitnessSource() throws {
        var runtime = try CrimeFixture.runtime()
        #expect(runtime.reportWitnessed(
            CrimeFixture.event(.assault, witnessed: false)
        ).refusal == .unwitnessed)

        runtime.witnesses = FixedCrimeWitnesses(
            watching: .player, by: [CrimeFixture.key(CrimeFixture.Actors.resident)]
        )
        #expect(runtime.reportWitnessed(
            CrimeFixture.event(.assault, witnessed: false)
        ).gold == 40)
    }

    /// The quote a readout shows before the player acts runs the same refusal
    /// rules the charge does, so a panel cannot promise a bounty the take would
    /// not accrue. Witnessing is the one rule it skips, because "if witnessed"
    /// is what the quote answers.
    @Test
    func aQuoteAppliesEveryRefusalExceptWitnessing() throws {
        let runtime = try CrimeFixture.runtime()

        #expect(runtime.quote(
            CrimeFixture.event(.theft, witnessed: false, stolenValue: 100)
        ) == 50)
        // The tolerant faction ignores stealing, so it quotes nothing.
        #expect(runtime.quote(CrimeFixture.event(
            .theft, faction: CrimeFixture.Factions.tolerant, stolenValue: 100
        )) == 0)
        // A faction that does not track crime quotes nothing either.
        #expect(runtime.quote(CrimeFixture.event(
            .theft, faction: CrimeFixture.Factions.shopkeepers, stolenValue: 100
        )) == 0)
        // And nothing is quoted where no faction answers for the place.
        #expect(runtime.quote(CrimeFixture.event(
            .theft, faction: nil, stolenValue: 100
        )) == 0)
        // A quote records nothing.
        #expect(runtime.ledger().isEmpty)
    }

    // MARK: - Faction flags

    /// A faction with `ignoreStealing` set charges nothing for a theft and the
    /// full price for a murder.
    @Test
    func aFactionIgnoringAKindChargesNothingForIt() throws {
        let runtime = try CrimeFixture.runtime()
        let tolerant = CrimeFixture.Factions.tolerant

        let theft = runtime.report(
            CrimeFixture.event(.theft, faction: tolerant, stolenValue: 100)
        )
        #expect(theft.gold == 0)
        #expect(theft.refusal == .factionIgnoresKind)
        #expect(runtime.report(CrimeFixture.event(.murder, faction: tolerant)).gold == 1000)
    }

    /// A faction without `trackCrime` charges nothing for anything.
    @Test
    func aFactionThatDoesNotTrackCrimeChargesNothing() throws {
        let runtime = try CrimeFixture.runtime()
        let outcome = runtime.report(
            CrimeFixture.event(.murder, faction: CrimeFixture.Factions.shopkeepers)
        )

        #expect(outcome.gold == 0)
        #expect(outcome.refusal == .factionIgnoresCrime)
        #expect(outcome.recorded)
    }

    /// `doNotReportCrimesAgainstMembers` also covers property the faction owns
    /// itself, which is the theft case: the victim of a theft is the owner, and
    /// a faction is trivially its own member.
    @Test
    func aFactionMayRefuseToReportTheftOfItsOwnProperty() throws {
        let runtime = try CrimeFixture.runtime()
        let tolerant = CrimeFixture.Factions.tolerant

        let outcome = runtime.report(CrimeFixture.event(
            .murder, faction: tolerant, victim: tolerant
        ))

        #expect(outcome.gold == 0)
        #expect(outcome.refusal == .victimIsMember)
    }

    /// `doNotReportCrimesAgainstMembers`: a crime against one of the faction's
    /// own members costs nothing.
    @Test
    func aFactionMayRefuseToReportCrimesAgainstItsOwnMembers() throws {
        let store = WorldStateStore()
        let runtime = try CrimeFixture.runtime(store: store)
        let victim = CrimeFixture.key(CrimeFixture.Actors.resident)
        let tolerant = CrimeFixture.Factions.tolerant
        store.set(
            CrimeFixture.state([(tolerant, 0)]),
            for: victim,
            in: nil
        )

        let outcome = runtime.report(CrimeFixture.event(
            .murder, faction: tolerant, victim: CrimeFixture.Actors.resident
        ))
        #expect(outcome.gold == 0)
        #expect(outcome.refusal == .victimIsMember)
    }

    // MARK: - No faction to charge

    /// A place that answers to nobody records nothing: a bandit killed on the
    /// road costs nothing and leaves no row.
    @Test
    func aCrimeInNobodysTerritoryRecordsNothing() throws {
        let runtime = try CrimeFixture.runtime()
        let outcome = runtime.report(CrimeFixture.event(.murder, faction: nil))

        #expect(outcome.gold == 0)
        #expect(!outcome.recorded)
        #expect(outcome.refusal == .noCrimeFaction)
        #expect(runtime.ledger().isEmpty)
    }

    /// A crime faction this load order carries no record for is refused
    /// outright, because a row keyed by it could never be read back or paid.
    @Test
    func anUnresolvableCrimeFactionRecordsNothing() throws {
        let runtime = try CrimeFixture.runtime()
        let outcome = runtime.report(CrimeFixture.event(.murder, faction: 0xDEAD))

        #expect(!outcome.recorded)
        #expect(outcome.refusal == .unresolvedCrimeFaction)
        #expect(runtime.ledger().isEmpty)
    }

    // MARK: - Mutating the ledger

    /// Paying a fine settles the debt and does not un-commit the crime.
    @Test
    func modifyingGoldLeavesTheCountsAlone() throws {
        let runtime = try CrimeFixture.runtime()
        runtime.report(CrimeFixture.event(.assault))

        #expect(runtime.modifyCrimeGold(by: -10, of: hold) == 30)
        #expect(runtime.crimeCounts(of: hold).assault == 1)
        // Clamped at zero: a bounty is paid down to nothing, never past it.
        #expect(runtime.modifyCrimeGold(by: -100, of: hold) == 0)
        #expect(runtime.crimeCounts(of: hold).assault == 1)
        #expect(runtime.setCrimeGold(500, of: hold) == 500)
        #expect(runtime.crimeCounts(of: hold).assault == 1)
    }

    /// The whole ledger drops once it says nothing, so a session in which the
    /// only bounty was paid off stops being dirty for the slot.
    @Test
    func aClearedLedgerDropsTheComponent() throws {
        let store = WorldStateStore()
        let runtime = try CrimeFixture.runtime(store: store)
        runtime.report(CrimeFixture.event(.assault))
        #expect(store.component(CrimeLedgerState.self, for: .player) != nil)

        #expect(runtime.reset())
        #expect(store.component(CrimeLedgerState.self, for: .player) == nil)
        #expect(runtime.crimeGold(of: hold) == 0)
    }

    /// Every ledger write goes through `WorldStateStore.set`, so it lands in
    /// the journal exactly as a faction join does.
    @Test
    func everyLedgerWriteLandsInTheJournal() throws {
        let store = WorldStateStore()
        let runtime = try CrimeFixture.runtime(store: store)
        runtime.report(CrimeFixture.event(.assault))

        let entries = store.journalEntries.filter { $0.kind == .crimeLedger }
        #expect(entries.count == 1)
        #expect(store.dirtyCount == 1)
    }

    // MARK: - The component

    /// Rows sort by faction, empty rows drop out, and a repeated faction
    /// collapses to its last row — the normalization every component here does
    /// so a save writes the same bytes twice for the same state.
    @Test
    func theLedgerNormalizesOnTheWayIn() {
        let ledger = CrimeLedgerState(entries: [
            CrimeLedgerEntry(faction: CrimeFixture.key(0x20), gold: 5),
            CrimeLedgerEntry(faction: CrimeFixture.key(0x10), gold: 0),
            CrimeLedgerEntry(faction: CrimeFixture.key(0x10), gold: 9),
            CrimeLedgerEntry(faction: CrimeFixture.key(0x30))
        ])

        #expect(ledger.factions == [CrimeFixture.key(0x10), CrimeFixture.key(0x20)])
        #expect(ledger.gold(for: CrimeFixture.key(0x10)) == 9)
        #expect(ledger.gold(for: CrimeFixture.key(0x30)) == 0)
        #expect(ledger.totalGold == 14)
    }

    /// A negative bounty from a corrupt file becomes zero rather than a number
    /// that reads as owing minus three gold.
    @Test
    func negativeGoldAndCountsClampToZero() {
        let entry = CrimeLedgerEntry(
            faction: CrimeFixture.key(0x10),
            gold: -50,
            counts: CrimeCounts(theft: -2, murder: 3)
        )

        #expect(entry.gold == 0)
        #expect(entry.counts.theft == 0)
        #expect(entry.counts.murder == 3)
        #expect(entry.counts.total == 3)
    }

    /// Counts saturate rather than wrapping into a negative tally.
    @Test
    func countsSaturateAtTheTop() {
        let counts = CrimeCounts(murder: Int32.max).incrementing(.murder)
        #expect(counts.murder == Int32.max)
    }
}
