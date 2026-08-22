// The one place a condition asks "what does this actor owe?" (issue #504,
// roadmap item 21.5), mirroring `PerkConditionResolution` and
// `MagicConditionResolution`.
//
// Shaped as a resolved snapshot rather than as a live handle for the reason
// every other seam on `ConditionContext` is: the evaluator is a nonisolated
// value a build thread may run, so a condition body cannot reach into
// `WorldStateStore` or `CrimeRuntime`. The caller that *is* on the main actor
// reads the ledgers and hands the result over.
//
// The FACT store rides along beside the per-actor ledgers because
// `GetCrimeGold` takes a `ptFactionNull` parameter that has to be resolved
// against the load order before it can be looked up — exactly as the perk seam
// resolves its `ptPerk`.
//
// `currentCrimeFaction` is what a *null* parameter means. The Creation Kit
// declares the parameter nullable, and a condition that leaves it null is
// asking about the hold the subject is standing in rather than about no faction
// at all; the caller resolves that through `CrimeFactionResolver` and puts the
// answer here, because a `ConditionContext` carries no cell.
//
// Documented in docs/engine/crime.md and docs/formats/conditions.md.

import Foundation

/// Every actor's crime ledger plus the store a faction parameter resolves
/// against.
///
/// `@unchecked Sendable` for the reason `PerkConditionResolution` is: the store
/// is an immutable value snapshot built once at load, and only its
/// `RecordIndex` back-reference keeps it from being checked automatically.
nonisolated struct CrimeConditionResolution: @unchecked Sendable {
    /// Load-order FACT lookup, for the `ptFactionNull` parameter. Nil in a
    /// session with no faction data, which is what makes `GetCrimeGold` report
    /// a gap rather than answering "owes nothing" for every actor in the game.
    let factions: FactionStore?
    /// The plugin a condition's FormID parameters are spelled against.
    let sourcePlugin: String?
    /// The faction a null parameter means: the one answering for where the
    /// subject currently stands. Nil outside any hold, where a null-parameter
    /// condition has nothing to ask about.
    let currentCrimeFaction: ReferenceKey?

    private let ledgers: [ReferenceKey: CrimeLedgerState]

    static let empty = CrimeConditionResolution()

    init(
        factions: FactionStore? = nil,
        sourcePlugin: String? = nil,
        currentCrimeFaction: ReferenceKey? = nil,
        ledgers: [ReferenceKey: CrimeLedgerState] = [:]
    ) {
        self.factions = factions
        self.sourcePlugin = sourcePlugin
        self.currentCrimeFaction = currentCrimeFaction
        self.ledgers = ledgers
    }

    /// Whether the seam can answer at all: a session with no FACT store cannot,
    /// and says so rather than answering zero everywhere.
    var isAvailable: Bool {
        factions != nil
    }

    /// One faction parameter as the runtime identity the ledger is keyed by, or
    /// the current crime faction when the parameter is null.
    ///
    /// The record has to exist, not merely resolve — the rule the perk and
    /// keyword seams apply for the same reason: plugin-relative resolution
    /// answers for any FormID whose plugin is loaded, so a parameter naming a
    /// faction no plugin defines would otherwise come back as an ordinary key
    /// and read as "owes this faction nothing", which is a different answer
    /// from "this engine has no such faction".
    func key(of formID: FormID) -> ReferenceKey? {
        guard !formID.isNull else { return currentCrimeFaction }
        guard
            let sourcePlugin,
            let factions,
            let resolved = factions.resolvedID(formID, fromPlugin: sourcePlugin),
            factions.faction(resolved) != nil
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }

    /// Crime gold `actor` owes `faction`, or nil when no crime data is wired.
    ///
    /// An actor with no ledger owes nothing, which is a real answer rather than
    /// a gap: owing nobody anything is the normal state, and every actor in the
    /// game starts there.
    func crimeGold(of faction: ReferenceKey, on actor: ReferenceKey) -> Int32? {
        guard isAvailable else { return nil }
        return ledgers[actor]?.gold(for: faction) ?? 0
    }
}
