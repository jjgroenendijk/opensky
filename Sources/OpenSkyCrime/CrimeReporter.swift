// The one door every crime hook goes through. `CrimeRuntime` decides what a crime
// costs; this decides what the crime was, using `CrimeWorld` for cells, owners and
// values. A hook reports in one call and tests use a fake world. A class, because
// several hooks share one reporter and its witness source. See docs/engine/crime.md.

import Foundation
import OpenSkyConditions
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
    /// Takes `ADCR` and `ASSU`.
    public weak var storyEvents: (any StoryEventReporting)?
    /// The crime faction and the gold, each time a crime by the player costs gold.
    public var onPlayerBounty: ((ReferenceKey, Int32) -> Void)?
    /// Each crime that cost gold, with who saw it, so the report can wait for a guard.
    public var onCrimeCharged: ((CrimeEvent, CrimeOutcome, [ReferenceKey]) -> Void)?
    /// Each crime recorded, seen or not, for the journal's crime stats.
    public var onCrimeRecorded: ((CrimeEvent, CrimeOutcome) -> Void)?

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
    /// refuse the charge refuse the quote: a readout must not promise a bounty the
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
        record(
            theftEvent(item, count: count, from: reference, by: actor, owner: owner)
        )
    }

    /// Reports riding `horse`, which `owner` owns: a theft of `iCrimeGoldStealHorse`.
    @discardableResult
    public func reportHorseTheft(
        of horse: ReferenceKey, owner: ReferenceOwner?, by actor: ReferenceKey = .player
    ) -> CrimeOutcome {
        let cell = world?.crimeCell(of: horse)
        var event = CrimeEvent(
            kind: .theft, perpetrator: actor, victim: owner.map(\.key),
            crimeFaction: world?.crimeFaction(in: cell), cell: cell,
            stolenValue: Int64(runtime.settings.stolenHorseValue)
        )
        event.stolenCount = 1
        return record(event)
    }

    /// Reports the first blow against an actor that was not already hostile
    /// (<https://en.uesp.net/wiki/Skyrim:Crime>). The combat runtime knows both
    /// facts, so this records what it is told.
    @discardableResult
    public func reportAssault(
        on victim: ReferenceKey,
        by actor: ReferenceKey = .player
    ) -> CrimeOutcome {
        record(event(.assault, victim: victim, by: actor))
    }

    /// Reports a non-hostile actor dying.
    @discardableResult
    public func reportMurder(
        of victim: ReferenceKey,
        by actor: ReferenceKey = .player
    ) -> CrimeOutcome {
        record(event(.murder, victim: victim, by: actor))
    }

    /// A failed pickpocket: the target noticed, so it is witnessed, and it costs the
    /// `CRVA` pickpocket price (<https://en.uesp.net/wiki/Skyrim:Pickpocket>).
    @discardableResult
    public func reportPickpocket(
        of victim: ReferenceKey,
        by actor: ReferenceKey = .player
    ) -> CrimeOutcome {
        let base = event(.pickpocket, victim: victim, by: actor)
        return recordAsIs(CrimeEvent(
            kind: .pickpocket, perpetrator: actor, victim: victim,
            crimeFaction: base.crimeFaction, cell: base.cell, witnessed: true
        ))
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
        record(CrimeEvent(
            kind: .trespass,
            perpetrator: actor,
            victim: owner.map(\.key),
            crimeFaction: world?.crimeFaction(in: cell),
            cell: cell
        ))
    }

    /// `Game.SendWereWolfTransformation`: "Has an actor in high who can detect the
    /// player call a werewolf crime against the player"
    /// (<https://ck.uesp.net/wiki/SendWereWolfTransformation_-_Game>). The first actor
    /// that detects `actor` calls it. Nil when nobody does.
    @discardableResult
    public func reportWerewolfTransformation(by actor: ReferenceKey = .player) -> CrimeOutcome? {
        guard let witness = runtime.witnesses.witnesses(of: actor).first else { return nil }
        let located = event(.werewolf, victim: witness, by: actor)
        return recordAsIs(CrimeEvent(
            kind: .werewolf, perpetrator: actor, victim: witness,
            crimeFaction: located.crimeFaction, cell: located.cell, witnessed: true
        ))
    }

    /// Leaving jail early, charged to the hold that jailed the player at its `CRVA`
    /// escape price. The guards know at once, so it needs no witness.
    @discardableResult
    public func reportEscape(from faction: ReferenceKey, by actor: ReferenceKey = .player)
        -> CrimeOutcome
    {
        recordAsIs(CrimeEvent(
            kind: .escape, perpetrator: actor, crimeFaction: faction, witnessed: true
        ))
    }

    // MARK: - Private

    /// `ASSU` for every assault, `ADCR` when the crime cost gold.
    private func record(_ event: CrimeEvent) -> CrimeOutcome {
        recordAsIs(event.witnessed(by: runtime.witnesses))
    }

    private func recordAsIs(_ event: CrimeEvent) -> CrimeOutcome {
        let outcome = runtime.report(event)
        onCrimeRecorded?(event, outcome)
        if event.kind == .assault, let victim = event.victim {
            storyEvents?.reportStoryEvent(.assault(
                attacker: event.perpetrator, victim: victim, location: nil
            ))
        }
        if outcome.gold > 0, let faction = outcome.faction {
            if event.perpetrator == .player {
                onPlayerBounty?(faction, outcome.gold)
            }
            let witnesses: [ReferenceKey] = switch event.kind {
            case .pickpocket: event.victim.map { [$0] } ?? []
            case .escape: []
            default: runtime.witnesses.witnesses(of: event.perpetrator)
            }
            onCrimeCharged?(event, outcome, witnesses)
            storyEvents?.reportStoryEvent(.crimeGold(
                criminal: event.perpetrator,
                victim: event.victim,
                crimeFaction: faction,
                gold: outcome.gold,
                crime: event.kind.storyCrimeType
            ))
        }
        return outcome
    }

    private func theftEvent(
        _ item: FormID,
        count: Int32,
        from reference: ReferenceKey,
        by actor: ReferenceKey,
        owner: ReferenceOwner?
    ) -> CrimeEvent {
        let cell = world?.crimeCell(of: reference)
        let unitValue = world?.crimeItemValue(of: item) ?? 0
        var event = CrimeEvent(
            kind: .theft,
            perpetrator: actor,
            victim: owner.map(\.key),
            crimeFaction: world?.crimeFaction(in: cell),
            cell: cell,
            stolenValue: unitValue * Int64(max(0, count))
        )
        event.stolenCount = max(0, count)
        return event
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

extension CrimeKind {
    var storyCrimeType: StoryCrimeType {
        switch self {
        case .theft: .steal
        case .pickpocket: .pickpocket
        case .escape: .escapeJail
        case .assault: .assault
        case .murder: .murder
        case .trespass: .trespass
        case .werewolf: .werewolf
        }
    }
}
