// Crime at runtime: turns a crime into a bounty on a crime faction, writing
// through `WorldStateStore.set`. Order: a faction to charge; it tracks crime
// and does not ignore this kind; a witness saw it
// (<https://en.uesp.net/wiki/Skyrim:Crime>); the price from `CrimeGoldTable`.
// The count moves even when nobody saw. See docs/engine/crime.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// Reads and mutates crime ledgers on top of a `WorldStateStore`, and decides
/// what one reported crime costs.
@MainActor
public struct CrimeRuntime {
    /// Load-order FACT lookup, for the flags and the `CRVA` block behind every
    /// bounty.
    public let factions: FactionStore
    /// Where "did anybody see?" is answered. Assignable rather than injected at
    /// init so a session can attach the perception pass once it exists, exactly
    /// as `HostilityDerivation.crime` is assignable.
    public var witnesses: any CrimeWitnessSource = NoCrimeWitnesses()

    private let worldState: WorldStateStore

    public init(
        store: WorldStateStore,
        factions: FactionStore,
        witnesses: any CrimeWitnessSource = NoCrimeWitnesses()
    ) {
        worldState = store
        self.factions = factions
        self.witnesses = witnesses
    }

    // MARK: - Reading

    /// `key`'s ledger, empty when nothing has ever written one.
    public func ledger(of key: ReferenceKey = .player) -> CrimeLedgerState {
        worldState.component(CrimeLedgerState.self, for: key) ?? .empty
    }

    /// Crime gold `key` owes `faction`.
    public func crimeGold(of faction: ReferenceKey, on key: ReferenceKey = .player) -> Int32 {
        ledger(of: key).gold(for: faction)
    }

    /// How many crimes of each kind `key` has committed against `faction`.
    public func crimeCounts(
        of faction: ReferenceKey,
        on key: ReferenceKey = .player
    ) -> CrimeCounts {
        ledger(of: key).counts(for: faction)
    }

    // MARK: - Reporting

    /// Records one crime: the count always, the gold when it is owed.
    ///
    /// - Returns: what was charged and, when nothing was, why not.
    @discardableResult
    public func report(_ event: CrimeEvent) -> CrimeOutcome {
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

    /// What a witnessed `event` would cost, without recording anything. The quote
    /// runs the same refusal rules as `report`, except the witness check.
    public func quote(_ event: CrimeEvent) -> Int32 {
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
    public func reportWitnessed(_ event: CrimeEvent) -> CrimeOutcome {
        report(event.witnessed(by: witnesses))
    }

    // MARK: - Mutating the ledger

    /// One half of `key`'s bounty with `faction`.
    public func crimeGold(
        of faction: ReferenceKey,
        violent: Bool,
        on key: ReferenceKey = .player
    ) -> Int32 {
        ledger(of: key).gold(for: faction, violent: violent)
    }

    /// Moves one half of `key`'s bounty with `faction` by `delta`, clamped at
    /// zero, leaving the crime counts alone. The door `Faction.ModCrimeGold`
    /// comes through, with its `abViolent` flag choosing the half.
    ///
    /// - Returns: the combined bounty afterwards.
    @discardableResult
    public func modifyCrimeGold(
        by delta: Int32,
        violent: Bool = false,
        of faction: ReferenceKey,
        on key: ReferenceKey = .player,
        in cell: CellSceneLocation? = nil
    ) -> Int32 {
        write(
            ledger(of: key).modifyingGold(by: delta, violent: violent, for: faction),
            for: key,
            in: cell
        )
        return crimeGold(of: faction, on: key)
    }

    /// Sets one half of `key`'s bounty with `faction` outright, leaving the
    /// other half and the counts alone. `Faction.SetCrimeGold` sets the
    /// non-violent half and `Faction.SetCrimeGoldViolent` the violent one.
    ///
    /// - Returns: the combined bounty afterwards.
    @discardableResult
    public func setCrimeGold(
        _ gold: Int32,
        violent: Bool = false,
        of faction: ReferenceKey,
        on key: ReferenceKey = .player,
        in cell: CellSceneLocation? = nil
    ) -> Int32 {
        write(
            ledger(of: key).settingGold(gold, violent: violent, for: faction),
            for: key,
            in: cell
        )
        return crimeGold(of: faction, on: key)
    }

    /// Clears both halves of `key`'s bounty with `faction`, keeping the counts.
    /// What paying a fine and serving a sentence both do.
    ///
    /// - Returns: the gold that was owed.
    @discardableResult
    public func clearCrimeGold(
        of faction: ReferenceKey,
        on key: ReferenceKey = .player,
        in cell: CellSceneLocation? = nil
    ) -> Int32 {
        let owed = crimeGold(of: faction, on: key)
        write(ledger(of: key).clearingGold(for: faction), for: key, in: cell)
        return owed
    }

    /// Drops `key`'s whole ledger, bounties and counts alike. The reset a dev
    /// panel and a new game both need.
    ///
    /// - Returns: true when there was a ledger to drop.
    @discardableResult
    public func reset(on key: ReferenceKey = .player) -> Bool {
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

    /// Whether the crime's victim belongs to the faction that would charge for it: a
    /// placed actor by its memberships, or the faction itself. A theft from an
    /// NPC_-owned reference cannot check this, because `XOWN` names a base record
    /// (docs/engine/crime.md).
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
    public func witnessed(by source: any CrimeWitnessSource) -> CrimeEvent {
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
