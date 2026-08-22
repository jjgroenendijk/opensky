// The one door every crime hook goes through (issue #504, roadmap item 21.5).
//
// `CrimeRuntime` decides what a described crime costs; this decides what the
// crime *was*. Between them sits `CrimeWorld`, which is everything about the
// running session a crime needs and neither of those two can reach: which
// reference stands in which cell, what that cell's `XOWN` says, which crime
// faction answers for it, and what an item is worth.
//
// The split is the shape `MeleeCombatWorld` and `PerceptionWorld` already take,
// and for the same reason: the hooks — a take in `WorldItemRuntime`, a blow in
// the melee world, a death — must be able to say "this happened" in one call
// without assembling a `CrimeEvent` each, and the assembly must be testable
// against a fake world rather than a streamed cell.
//
// A class rather than a struct because the session hands the same reporter to
// several hooks and then attaches the perception pass to it afterwards; a
// struct would give each hook its own copy of the witness source.
//
// Documented in docs/engine/crime.md.

import Foundation

/// Everything about the running session a crime needs to know.
@MainActor
protocol CrimeWorld: AnyObject {
    /// The owner in force for one resident reference: its own `XOWN`, else the
    /// owner of the cell it stands in (`OwnershipResolver`). Nil when nothing
    /// claims it, and also when nothing resident is that reference — a
    /// reference the session cannot see is not one it can call owned.
    func crimeOwner(of key: ReferenceKey) -> ReferenceOwner?

    /// The crime faction answering for `cell`, walking the location parent
    /// chain (`CrimeFactionResolver`). Nil where the place belongs to nobody.
    func crimeFaction(in cell: CellSceneLocation?) -> ReferenceKey?

    /// Which cell a resident reference stands in, so a crime is attributed to
    /// the cell whose rebuild makes it visible.
    func crimeCell(of key: ReferenceKey) -> CellSceneLocation?

    /// One item's authored gold value, which is what a theft bounty is scaled
    /// from. Zero for a form no loaded plugin describes — the same answer
    /// `InventoryRuntime.carriedValue` gives, because inventing a value would
    /// put a number the data never authored into a bounty.
    func crimeItemValue(of item: FormID) -> Int64

    /// Who is acting, with the memberships an ownership check needs.
    func crimeActor(_ key: ReferenceKey) -> CrimeActor
}

/// Turns things that happened into ledger entries.
@MainActor
final class CrimeReporter {
    /// The ledger and the pricing behind it. A `var` because the witness source
    /// is attached after construction, exactly as `HostilityDerivation.crime`
    /// is.
    var runtime: CrimeRuntime
    /// The session the facts come from. Weak because the controller that owns
    /// this owns the session too.
    weak var world: (any CrimeWorld)?

    init(runtime: CrimeRuntime, world: (any CrimeWorld)? = nil) {
        self.runtime = runtime
        self.world = world
    }

    /// Where "did anybody see?" is answered, forwarded so a session can attach
    /// the perception pass without reaching through to the runtime.
    var witnesses: any CrimeWitnessSource {
        get { runtime.witnesses }
        set { runtime.witnesses = newValue }
    }

    // MARK: - Asking before acting

    /// What `actor` may do with `reference` right now.
    ///
    /// The question a take asks before it takes, and the one an inspector shows
    /// under the crosshair. A session with no world answers `.unowned`, which
    /// is the pre-crime behaviour rather than a new wrong answer.
    func verdict(
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
    func theftBounty(
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
    func reportTheft(
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

    /// Reports the first blow against an actor that was not already hostile.
    ///
    /// "Initiating combat or using a hostile spell effect on an NPC will incur
    /// a bounty ... Self-defense against an unprovoked assault is legal and not
    /// considered a crime" (<https://en.uesp.net/wiki/Skyrim:Crime>). Which
    /// blow is the first and whether the victim was already hostile is the
    /// caller's to know — the combat runtime holds both — so this records what
    /// it is told.
    @discardableResult
    func reportAssault(
        on victim: ReferenceKey,
        by actor: ReferenceKey = .player
    ) -> CrimeOutcome {
        runtime.reportWitnessed(event(.assault, victim: victim, by: actor))
    }

    /// Reports a non-hostile actor dying.
    @discardableResult
    func reportMurder(
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
    func reportTrespass(
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
