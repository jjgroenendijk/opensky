// The guard and arrest half of the Papyrus world seam (issue #505, roadmap item
// 21.6), declared beside the crime and faction halves and refined into
// `PapyrusWorldBridge` the same way.
//
// Five operations: which crime faction an actor reports to, whether it is a
// guard, whether the player can pay a bounty, and the two ways an arrest ends.
// The ledger and inventory writes go through `CrimeArrest` inside the session,
// so a scripted payment and one chosen in the arrest conversation reach the
// store by one path.
//
// Documented in docs/engine/papyrus-activation.md and docs/engine/guard-response.md.

import Foundation

/// Guard and arrest operations a Papyrus native may perform.
@MainActor
protocol PapyrusWorldGuardBridge {
    /// The crime faction `actor` reports to — its `CRIF` — as `.some(nil)` when
    /// it names none, or nil for a session with no faction data.
    ///
    /// "Obtains the Faction this actor reports it's crimes to."
    /// (<https://ck.uesp.net/wiki/GetCrimeFaction_-_Actor>)
    func crimeFaction(ofActor actor: ReferenceKey) -> ReferenceKey??

    /// Whether `actor` is a guard, or nil for a session with no faction data.
    ///
    /// "Is this actor a guard?" (<https://ck.uesp.net/wiki/IsGuard_-_Actor>)
    /// A guard is a member of the `GFAC` faction that reports to a crime
    /// faction; see `GuardRecognition`.
    func isGuard(_ actor: ReferenceKey) -> Bool?

    /// "Checks to see if the player can pay the crime gold for this faction."
    /// (<https://ck.uesp.net/wiki/CanPayCrimeGold_-_Faction>) Nil for a session
    /// with no crime runtime.
    func canPayCrimeGold(to faction: ReferenceKey) -> Bool?

    /// Runs one arrest outcome, or nil for a session with no crime runtime.
    func settleArrest(
        with faction: ReferenceKey,
        _ outcome: ArrestOutcome
    ) -> Result<ArrestSettlement, ArrestRefusal>?
}

extension PapyrusWorldStateBridge {
    func crimeFaction(ofActor actor: ReferenceKey) -> ReferenceKey?? {
        guard let profile = socialProfile?(actor) else { return nil }
        return .some(profile.crimeFaction)
    }

    func isGuard(_ actor: ReferenceKey) -> Bool? {
        guard
            let profile = socialProfile?(actor),
            let runtime = factionRuntime?(actor)
        else { return nil }
        return GuardRecognition.policedFaction(
            of: profile,
            guardFaction: runtime.factions.guardFactionKey
        ) != nil
    }

    func canPayCrimeGold(to faction: ReferenceKey) -> Bool? {
        arrestSession?()?.canPayCrimeGold(to: faction)
    }

    func settleArrest(
        with faction: ReferenceKey,
        _ outcome: ArrestOutcome
    ) -> Result<ArrestSettlement, ArrestRefusal>? {
        arrestSession?()?.settleArrest(with: faction, outcome)
    }
}

/// Nonisolated hops, one `MainActor.assumeIsolated` per method, mirroring the
/// rest of `PapyrusWorldAccess`.
nonisolated extension PapyrusWorldAccess {
    func crimeFaction(ofActor actor: ReferenceKey) -> ReferenceKey?? {
        MainActor.assumeIsolated { bridge.crimeFaction(ofActor: actor) }
    }

    func isGuard(_ actor: ReferenceKey) -> Bool? {
        MainActor.assumeIsolated { bridge.isGuard(actor) }
    }

    func canPayCrimeGold(to faction: ReferenceKey) -> Bool? {
        MainActor.assumeIsolated { bridge.canPayCrimeGold(to: faction) }
    }

    func settleArrest(
        with faction: ReferenceKey,
        _ outcome: ArrestOutcome
    ) -> Result<ArrestSettlement, ArrestRefusal>? {
        MainActor.assumeIsolated { bridge.settleArrest(with: faction, outcome) }
    }
}
