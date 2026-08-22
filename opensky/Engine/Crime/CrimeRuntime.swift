// Crime at runtime (issue #504, roadmap item 21.5): the layer that turns "an
// owned thing was taken" into a bounty on a crime faction.
//
// A thin layer beside `WorldStateStore`, following `FactionRuntime`,
// `PerkRuntime` and `InventoryRuntime`. Every mutation writes through
// `WorldStateStore.set`, so accruing a bounty lands in the journal, in the
// dirty counts and in the save exactly as joining a faction does.
//
// Headless and AppKit-free: this compiles into `openskycli` and is testable
// without a window. `@MainActor` only because the store it writes to is.
//
// ## The decision, in order
//
// 1. **Is there a faction to charge?** `CrimeEvent.crimeFaction`, resolved by
//    the caller through `CrimeFactionResolver`. None means the place belongs to
//    nobody, and nothing is recorded — a bandit killed on the road costs
//    nothing and leaves no row.
// 2. **Does that faction care?** `Faction.Flags.trackCrime` has to be set, and
//    the per-kind ignore bit (`ignoreStealing`, `ignoreAssault`, `ignoreMurder`,
//    `ignoreTrespass`) must not be. A faction with
//    `doNotReportCrimesAgainstMembers` set refuses a crime whose victim belongs
//    to it.
// 3. **Did anybody see?** Only a witnessed crime accrues gold. "If you are
//    caught doing an illegal action by a witness you will incur a bounty"
//    (<https://en.uesp.net/wiki/Skyrim:Crime>).
// 4. **How much?** `CrimeGoldTable` over the faction's own `CRVA`.
//
// The count moves either way, witnessed or not: "Regardless of whether a crime
// is witnessed, the Statistics tab on the menu keeps track of all your criminal
// activities" (same page). That is the difference an unwitnessed theft leaves
// behind — a count, no gold, and a stolen stack.
//
// Documented in docs/engine/crime.md.

import Foundation

/// What reporting one crime did, and why.
nonisolated struct CrimeOutcome: Equatable, Sendable {
    /// Why a crime accrued no gold, when it accrued none.
    enum Refusal: String, Equatable, Sendable {
        /// The place belongs to no crime faction, so there is nobody to charge.
        case noCrimeFaction
        /// This load order carries no FACT for the resolved crime faction.
        case unresolvedCrimeFaction
        /// The faction does not have `trackCrime` set.
        case factionIgnoresCrime
        /// The faction sets the ignore bit for this kind of crime.
        case factionIgnoresKind
        /// The faction does not report crimes against its own members, and the
        /// victim is one.
        case victimIsMember
        /// Nobody saw it.
        case unwitnessed
    }

    /// Gold added to the ledger, which is zero for every refusal.
    let gold: Int32
    /// The faction charged, or nil when nothing was charged.
    let faction: ReferenceKey?
    /// Whether the crime was counted at all, which is false only when there was
    /// no faction to count it against.
    let recorded: Bool
    /// Why no gold was charged, or nil when some was.
    let refusal: Refusal?

    /// Nothing happened, for a crime that reached no faction.
    static func refused(_ refusal: Refusal, faction: ReferenceKey? = nil) -> CrimeOutcome {
        CrimeOutcome(
            gold: 0,
            faction: faction,
            recorded: faction != nil && refusal != .unresolvedCrimeFaction,
            refusal: refusal
        )
    }
}

/// Reads and mutates crime ledgers on top of a `WorldStateStore`, and decides
/// what one reported crime costs.
@MainActor
struct CrimeRuntime {
    /// Load-order FACT lookup, for the flags and the `CRVA` block behind every
    /// bounty.
    let factions: FactionStore
    /// Where "did anybody see?" is answered. Assignable rather than injected at
    /// init so a session can attach the perception pass once it exists, exactly
    /// as `HostilityDerivation.crime` is assignable.
    var witnesses: any CrimeWitnessSource = NoCrimeWitnesses()

    private let worldState: WorldStateStore

    init(
        store: WorldStateStore,
        factions: FactionStore,
        witnesses: any CrimeWitnessSource = NoCrimeWitnesses()
    ) {
        worldState = store
        self.factions = factions
        self.witnesses = witnesses
    }

    var store: WorldStateStore {
        worldState
    }

    // MARK: - Reading

    /// `key`'s ledger, empty when nothing has ever written one.
    func ledger(of key: ReferenceKey = .player) -> CrimeLedgerState {
        worldState.component(CrimeLedgerState.self, for: key) ?? .empty
    }

    /// Crime gold `key` owes `faction`.
    func crimeGold(of faction: ReferenceKey, on key: ReferenceKey = .player) -> Int32 {
        ledger(of: key).gold(for: faction)
    }

    /// How many crimes of each kind `key` has committed against `faction`.
    func crimeCounts(of faction: ReferenceKey, on key: ReferenceKey = .player) -> CrimeCounts {
        ledger(of: key).counts(for: faction)
    }

    /// Total gold owed everywhere, which is UESP's "Total Lifetime Bounty".
    func totalCrimeGold(on key: ReferenceKey = .player) -> Int64 {
        ledger(of: key).totalGold
    }

    /// Every faction `key` owes something to or has offended, joined to the
    /// records, in ledger order. A row whose faction this load order dropped is
    /// kept in the ledger and simply absent here.
    func resolvedFactions(on key: ReferenceKey = .player) -> [ResolvedFaction] {
        ledger(of: key).factions.compactMap { factions.faction(key: $0) }
    }

    // MARK: - Reporting

    /// Records one crime: the count always, the gold when it is owed.
    ///
    /// - Returns: what was charged and, when nothing was, why not.
    @discardableResult
    func report(_ event: CrimeEvent) -> CrimeOutcome {
        guard let faction = event.crimeFaction else {
            return .refused(.noCrimeFaction)
        }
        guard let resolved = factions.faction(key: faction) else {
            // Recorded nowhere on purpose: a row keyed by a faction nothing
            // resolves could never be read back or paid off, which is the same
            // rule `FactionRuntime.join` applies to an unresolvable membership.
            return .refused(.unresolvedCrimeFaction, faction: faction)
        }
        if let refusal = refusal(for: event, by: resolved.faction, keyed: faction) {
            record(event, gold: 0, against: faction)
            return .refused(refusal, faction: faction)
        }
        let gold = CrimeGoldTable(faction: resolved.faction).bounty(for: event)
        record(event, gold: gold, against: faction)
        return CrimeOutcome(gold: gold, faction: faction, recorded: true, refusal: nil)
    }

    /// What a witnessed `event` would cost, without recording anything.
    ///
    /// The quote a readout shows under the crosshair before the player acts. It
    /// runs the same refusal rules `report` does — a faction that does not track
    /// crime, or ignores this kind, or will not report a crime against its own
    /// member charges nothing — so the panel cannot promise a bounty the take
    /// would not charge. The one rule it skips is witnessing, because "if
    /// witnessed" is exactly what the quote is answering.
    func quote(_ event: CrimeEvent) -> Int32 {
        guard
            let faction = event.crimeFaction,
            let resolved = factions.faction(key: faction),
            refusal(for: event, by: resolved.faction, keyed: faction, checkingWitness: false)
            == nil
        else { return 0 }
        return CrimeGoldTable(faction: resolved.faction).bounty(for: event)
    }

    /// The same report with witnessing resolved here rather than by the caller,
    /// which is what every hook in the engine actually wants: it holds the act,
    /// not the answer to "was anybody looking".
    @discardableResult
    func reportWitnessed(_ event: CrimeEvent) -> CrimeOutcome {
        report(event.witnessed(by: witnesses))
    }

    // MARK: - Mutating the ledger

    /// Moves `key`'s bounty with `faction` by `delta`, clamped at zero, leaving
    /// the crime counts alone. The door `Faction.ModCrimeGold` comes through.
    ///
    /// - Returns: the bounty afterwards.
    @discardableResult
    func modifyCrimeGold(
        by delta: Int32,
        of faction: ReferenceKey,
        on key: ReferenceKey = .player,
        in cell: CellSceneLocation? = nil
    ) -> Int32 {
        write(ledger(of: key).modifyingGold(by: delta, for: faction), for: key, in: cell)
        return crimeGold(of: faction, on: key)
    }

    /// Sets `key`'s bounty with `faction` outright, leaving the counts alone.
    /// The door `Faction.SetCrimeGold` comes through.
    ///
    /// - Returns: the bounty afterwards.
    @discardableResult
    func setCrimeGold(
        _ gold: Int32,
        of faction: ReferenceKey,
        on key: ReferenceKey = .player,
        in cell: CellSceneLocation? = nil
    ) -> Int32 {
        write(ledger(of: key).settingGold(gold, for: faction), for: key, in: cell)
        return crimeGold(of: faction, on: key)
    }

    /// Drops `key`'s whole ledger, bounties and counts alike. The reset a dev
    /// panel and a new game both need.
    ///
    /// - Returns: true when there was a ledger to drop.
    @discardableResult
    func reset(on key: ReferenceKey = .player) -> Bool {
        worldState.reset(.crimeLedger, for: key)
    }

    // MARK: - Private

    /// Why `faction` charges nothing for `event`, or nil when it charges.
    ///
    /// Flag names and values are xEdit's `wbFACT` DATA flags, which UESP's FACT
    /// page spells identically; `Faction.Flags` carries them.
    private func refusal(
        for event: CrimeEvent,
        by faction: Faction,
        keyed key: ReferenceKey,
        checkingWitness: Bool = true
    ) -> CrimeOutcome.Refusal? {
        guard faction.tracksCrime else { return .factionIgnoresCrime }
        guard !faction.flags.contains(event.kind.ignoreFlag) else { return .factionIgnoresKind }
        if
            faction.flags.contains(.doNotReportCrimesAgainstMembers),
            let victim = event.victim,
            isMember(victim, of: key)
        {
            return .victimIsMember
        }
        guard !checkingWitness || event.witnessed else { return .unwitnessed }
        return nil
    }

    /// Whether the crime's victim belongs to the faction that would charge for
    /// it.
    ///
    /// Two things count. A *placed actor* answers from its stored memberships,
    /// which is the assault and murder case. A victim that *is* the faction
    /// answers yes trivially, which is the theft-from-faction-property case —
    /// a shop owned by the hold it stands in.
    ///
    /// Stated limitation: a theft from an NPC_-owned reference cannot consult
    /// the flag at all. `XOWN` names a base record and `ActorFactionState` is
    /// keyed by a placement, so there is nothing to look the base up as; every
    /// ACHR placed from it would answer differently anyway. Recorded in
    /// docs/engine/crime.md rather than answered with the wrong actor's
    /// memberships.
    private func isMember(_ victim: ReferenceKey, of faction: ReferenceKey) -> Bool {
        victim == faction || memberships(of: victim).isMember(of: faction)
    }

    /// One more crime of this kind on the perpetrator's ledger.
    private func record(_ event: CrimeEvent, gold: Int32, against faction: ReferenceKey) {
        write(
            ledger(of: event.perpetrator).recording(event.kind, gold: gold, against: faction),
            for: event.perpetrator,
            in: event.cell
        )
    }

    private func memberships(of key: ReferenceKey) -> ActorFactionState {
        worldState.component(ActorFactionState.self, for: key) ?? ActorFactionState()
    }

    /// Stores `ledger`, dropping the whole component once it is empty so an
    /// actor that owes nothing stops being dirty for this slot.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    private func write(
        _ ledger: CrimeLedgerState,
        for key: ReferenceKey,
        in cell: CellSceneLocation?
    ) -> Bool {
        guard ledger != self.ledger(of: key) else { return false }
        if ledger.isEmpty {
            worldState.reset(.crimeLedger, for: key)
        } else {
            worldState.set(ledger, for: key, in: cell)
        }
        return true
    }
}

nonisolated extension CrimeEvent {
    /// This event with `witnessed` set from a witness source.
    @MainActor
    func witnessed(by source: any CrimeWitnessSource) -> CrimeEvent {
        guard !witnessed else { return self }
        return CrimeEvent(
            kind: kind,
            perpetrator: perpetrator,
            victim: victim,
            crimeFaction: crimeFaction,
            cell: cell,
            witnessed: source.isWitnessed(perpetrator),
            stolenValue: stolenValue
        )
    }
}
