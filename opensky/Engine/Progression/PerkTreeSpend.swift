// Spending a perk point (issue #499, roadmap item 20.6): the four rules a
// requested perk has to satisfy before `PerkRuntime.add` is allowed to see it,
// and the typed refusal it answers with when one does not hold.
//
// Kept apart from `PerkRuntime` deliberately. That layer is *ownership* — it
// grants what it is told to grant, because a quest, a script and a race all
// hand out perks that no tree gates. This layer is the *player's own spend*,
// and it is the only place the tree, the rank order and the skill requirement
// are enforced.
//
// ## The four rules, and where each comes from
//
// 1. **Not already owned.** Adding a perk twice is a point spent on nothing.
// 2. **Playable.** PERK `DATA` carries the flag; the Creation Kit's perk-tree
//    screen offers only playable perks, and a quest perk is not something a
//    point buys.
// 3. **Rank order.** Each rank of a vanilla chain is its own record joined by
//    `NNAM` (docs/engine/perks.md), so taking rank three means the record whose
//    `NNAM` names it must already be owned. `PerkStore.previousRank(of:)` is
//    that lookup.
// 4. **Tree parent.** A box `FNAM` marks parent-required is only reachable once
//    one of the boxes drawing a line into it is owned, unless the tree's entry
//    node is one of them (`PerkTreeIndex`).
//
//    A higher rank is *not* its own box — `AVOneHanded` puts `Armsman00` in a
//    box and none of `Armsman20` through `Armsman80`, read 2026-08-20 — so the
//    box a rank belongs to is found by walking `NNAM` back to the chain head.
//    Rule 3 already forces the ranks below it, so checking the head's parent
//    for a higher rank asks nothing the chain has not already answered.
// 5. **Record conditions.** The perk's own `CTDA` run is where vanilla states
//    the skill requirement. `Armsman20` on this machine reads
//    `GetBaseActorValue One-Handed >= 20` and `HasPerk Armsman00 == 1`,
//    measured 2026-08-20 with `openskycli record Armsman20`. Both are evaluated
//    through the ordinary condition machinery, so a mod's requirement is
//    honoured with no code here knowing what it asks.
//
// Rules 3 and 4 overlap rule 5 on vanilla data, and that is on purpose: vanilla
// authors the parent as a `HasPerk` condition *and* as a tree line, but neither
// is guaranteed — `Armsman00` carries no record conditions at all — so checking
// only one would let a differently-authored tree be climbed out of order.
//
// Documented in docs/engine/character-leveling.md.

import Foundation

/// Why a perk-point spend was refused.
///
/// Typed and exhaustive because item 20.7 turns each case into the reason a
/// tree node is drawn unavailable. Nothing here traps and nothing throws past
/// the caller: a request for a perk that does not exist is an answer, not a
/// crash.
nonisolated enum PerkSpendRefusal: Error, Equatable, Sendable {
    /// This load order carries no PERK record for the requested key.
    case unresolvedPerk
    /// The record's `DATA` playable flag is clear.
    case notPlayable
    /// The actor already owns it.
    case alreadyOwned
    /// No perk tree in this load order grants it, so no point can buy it.
    case notInPerkTree
    /// The chain rank below this one is unowned; carries the record to take
    /// first.
    case previousRankMissing(ReferenceKey)
    /// The box asks for a parent and none of the boxes reaching it is owned.
    case parentMissing
    /// The record's own condition run did not hold — a skill requirement, or a
    /// prerequisite the record states as `HasPerk`.
    case unmetCondition
}

/// Validates a requested perk against the tree, the chain and the record's own
/// conditions.
///
/// `@MainActor` only because reading ownership goes through `PerkRuntime`,
/// which writes to a main-actor store.
@MainActor
struct PerkTreeSpendValidator {
    /// Ownership plus the load-order PERK index.
    let runtime: PerkRuntime
    /// Where each perk sits in a skill tree.
    let trees: PerkTreeIndex
    let conditionRegistry: ConditionFunctionRegistry

    /// Depth cap for the walk back to a chain head, matching `PerkStore`'s own
    /// cap so a mod-authored `NNAM` loop cannot hang a click.
    private static let chainDepthCap = 32

    init(
        runtime: PerkRuntime,
        trees: PerkTreeIndex,
        conditionRegistry: ConditionFunctionRegistry = .standard
    ) {
        self.runtime = runtime
        self.trees = trees
        self.conditionRegistry = conditionRegistry
    }

    /// Whether `holder` may spend a point on `perk` right now.
    ///
    /// - Parameter conditions: the evaluation context the record's own `CTDA`
    ///   run is judged in. Its `perks` seam is rebuilt here from live ownership
    ///   for the reason `PerkRuntimeEvaluation` rebuilds it: a `HasPerk`
    ///   prerequisite has to read what the actor owns now, not what the caller
    ///   last published.
    /// - Returns: nil when the spend is allowed, and the rule that refused it
    ///   otherwise.
    func refusal(
        for perk: ReferenceKey,
        on holder: ActorValueHolder,
        conditions: ConditionContext
    ) -> PerkSpendRefusal? {
        guard let record = runtime.record(perk) else { return .unresolvedPerk }
        guard record.record.isPlayable else { return .notPlayable }
        guard !runtime.owns(perk, on: holder) else { return .alreadyOwned }
        guard let placement = placement(for: record) else { return .notInPerkTree }
        if let previous = runtime.perks.previousRank(of: record.id) {
            let key = ReferenceKey(resolved: previous.id)
            guard runtime.owns(key, on: holder) else {
                return .previousRankMissing(key)
            }
        }
        if placement.requiresParent, !placement.reachableFromRoot, !placement.parents.isEmpty {
            guard placement.parents.contains(where: { runtime.owns($0, on: holder) }) else {
                return .parentMissing
            }
        }
        guard passesRecordConditions(record, on: holder, conditions: conditions) else {
            return .unmetCondition
        }
        return nil
    }

    // MARK: - Private

    /// The tree box `record` belongs to: its own, or the box of the chain head
    /// it is a later rank of.
    private func placement(for record: ResolvedPerk) -> PerkTreePlacement? {
        var current = record
        for _ in 0 ..< Self.chainDepthCap {
            if let placement = trees.placement(of: ReferenceKey(resolved: current.id)) {
                return placement
            }
            guard let previous = runtime.perks.previousRank(of: current.id) else { return nil }
            current = previous
        }
        return nil
    }

    /// Whether the perk record's own condition run holds for `holder`.
    ///
    /// An empty run holds — `Armsman00` authors none. A run this engine cannot
    /// evaluate does *not*: `ConditionEvaluator` answers an unknown function
    /// with a reason-tagged false, so a perk gated on something unimplemented
    /// stays unbuyable rather than being bought for free. That is the reason
    /// `GetBaseActorValue` (277) and `GetLevel` (80) are registered by this
    /// item — between them they are what every vanilla perk requirement asks.
    private func passesRecordConditions(
        _ record: ResolvedPerk,
        on holder: ActorValueHolder,
        conditions: ConditionContext
    ) -> Bool {
        guard !record.record.conditions.conditions.isEmpty else { return true }
        var context = conditions
        context.perks = runtime.conditionResolution(
            for: [holder.key], sourcePlugin: record.sourcePlugin
        )
        context.subject = holder.key
        context.target = holder.key
        var evaluator = ConditionEvaluator(context: context, registry: conditionRegistry)
        return evaluator.evaluate(record.record.conditions).isTrue
    }
}
