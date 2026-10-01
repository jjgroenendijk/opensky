// The one door every crime hook goes through. `CrimeRuntime` decides what a crime
// costs; this decides what the crime was, using `CrimeWorld` for cells, owners and
// values. A hook reports in one call and tests use a fake world. A class, because
// several hooks share one reporter and its witness source. See docs/engine/crime.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData

/// Turns things that happened into ledger entries.
@MainActor
public final class CrimeReporter: CrimeReporting {
    /// The ledger and the pricing behind it. A `var` because the witness source
    /// is attached after construction, exactly as `HostilityDerivation.crime`
    /// is.
    public var runtime: CrimeRuntime
    /// The session the facts come from. Weak because the controller that owns
    /// this owns the session too.
    public weak var world: (any CrimeWorld)?

    public init(runtime: CrimeRuntime, world: (any CrimeWorld)? = nil) {
        self.runtime = runtime
        self.world = world
    }

    /// Where "did anybody see?" is answered, forwarded so a session can attach
    /// the perception pass without reaching through to the runtime.
    public var witnesses: any CrimeWitnessSource {
        get { runtime.witnesses }
        set { runtime.witnesses = newValue }
    }

    // MARK: - Asking before acting

    /// What `actor` may do with `reference` right now.
    ///
    /// The question a take asks before it takes, and the one an inspector shows
    /// under the crosshair. A session with no world answers `.unowned`, which
    /// is the pre-crime behaviour rather than a new wrong answer.
    public func verdict(
        on reference: ReferenceKey,
        by actor: ReferenceKey = .player
    ) -> OwnershipVerdict {
        guard let world else { return .unowned }
        return world.crimeActor(actor).verdict(on: world.crimeOwner(of: reference))
    }

    /// What taking `count` of `item` out of `reference` would cost if somebody
    /// saw it, before it is taken. Zero when the take would not be theft.
    ///
    /// Quoted through `CrimeRuntime.quote`, so the same faction flags that would
    /// refuse the charge refuse the quote: a panel must not promise a bounty the
    /// take will not accrue.
    public func theftBounty(
        of item: FormID,
        count: Int32,
        from reference: ReferenceKey,
        by actor: ReferenceKey = .player
    ) -> Int32 {
        let verdict = verdict(on: reference, by: actor)
        guard verdict.isTheft else { return 0 }
        return runtime.quote(
            theftEvent(item, count: count, from: reference, by: actor, owner: verdict.owner)
        )
    }

    // MARK: - Reporting

    /// Reports taking `count` of `item` out of `reference`, whose owner is
    /// `owner`.
    ///
    /// The owner is passed in rather than looked up again because the caller
    /// has just asked for the verdict and acted on it; resolving it twice is
    /// two chances for the world to have moved in between.
    @discardableResult
    public func reportTheft(
        of item: FormID,
        count: Int32,
        from reference: ReferenceKey,
        owner: ReferenceOwner?,
        by actor: ReferenceKey = .player
    ) -> CrimeOutcome {
        runtime.reportWitnessed(
            theftEvent(item, count: count, from: reference, by: actor, owner: owner)
        )
    }

    /// Reports the first blow against an actor that was not already hostile
    /// (<https://en.uesp.net/wiki/Skyrim:Crime>). The combat runtime knows both
    /// facts, so this records what it is told.
    @discardableResult
    public func reportAssault(
        on victim: ReferenceKey,
        by actor: ReferenceKey = .player
    ) -> CrimeOutcome {
        runtime.reportWitnessed(event(.assault, victim: victim, by: actor))
    }

    /// Reports a non-hostile actor dying.
    @discardableResult
    public func reportMurder(
        of victim: ReferenceKey,
        by actor: ReferenceKey = .player
    ) -> CrimeOutcome {
        runtime.reportWitnessed(event(.murder, victim: victim, by: actor))
    }

    /// Reports being somewhere an owner has not let this actor be.
    ///
    /// The cell is named rather than derived from the actor, because the caller
    /// that noticed the trespass is the one that knows which cell it noticed it
    /// in.
    @discardableResult
    public func reportTrespass(
        in cell: CellSceneLocation?,
        owner: ReferenceOwner?,
        by actor: ReferenceKey = .player
    ) -> CrimeOutcome {
        runtime.reportWitnessed(CrimeEvent(
            kind: .trespass,
            perpetrator: actor,
            victim: owner.map(\.key),
            crimeFaction: world?.crimeFaction(in: cell),
            cell: cell
        ))
    }

    // MARK: - Private

    private func theftEvent(
        _ item: FormID,
        count: Int32,
        from reference: ReferenceKey,
        by actor: ReferenceKey,
        owner: ReferenceOwner?
    ) -> CrimeEvent {
        let cell = world?.crimeCell(of: reference)
        let unitValue = world?.crimeItemValue(of: item) ?? 0
        return CrimeEvent(
            kind: .theft,
            perpetrator: actor,
            victim: owner.map(\.key),
            crimeFaction: world?.crimeFaction(in: cell),
            cell: cell,
            stolenValue: unitValue * Int64(max(0, count))
        )
    }

    /// An event against one actor, located by where that actor stands.
    private func event(
        _ kind: CrimeKind,
        victim: ReferenceKey,
        by actor: ReferenceKey
    ) -> CrimeEvent {
        let cell = world?.crimeCell(of: victim) ?? world?.crimeCell(of: actor)
        return CrimeEvent(
            kind: kind,
            perpetrator: actor,
            victim: victim,
            crimeFaction: world?.crimeFaction(in: cell),
            cell: cell
        )
    }
}

extension CrimeReporter {
    @discardableResult
    public func report(_ event: CrimeEvent) -> CrimeOutcome {
        runtime.report(event)
    }

    public func crimeGold(of faction: ReferenceKey) -> Int32 {
        runtime.crimeGold(of: faction)
    }

    public func crimeGold(of faction: ReferenceKey, violent: Bool) -> Int32 {
        runtime.crimeGold(of: faction, violent: violent)
    }

    @discardableResult
    public func modifyCrimeGold(by delta: Int32, violent: Bool, of faction: ReferenceKey) -> Int32 {
        runtime.modifyCrimeGold(by: delta, violent: violent, of: faction)
    }

    @discardableResult
    public func setCrimeGold(_ gold: Int32, violent: Bool, of faction: ReferenceKey) -> Int32 {
        runtime.setCrimeGold(gold, violent: violent, of: faction)
    }
}
