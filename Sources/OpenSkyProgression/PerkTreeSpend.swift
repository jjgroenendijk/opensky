// Spending a perk point. `PerkRuntime` grants whatever it is told; this layer
// enforces the player's own spend: not owned, playable, previous rank owned
// (`NNAM`), tree parent owned (`PerkTreeIndex`, checked at the chain head), and the
// perk's `CTDA` run, where an unknown function holds. Vanilla states parents both as
// `HasPerk` and as tree lines, but not always, so both are checked. See
// docs/engine/character-leveling.md.

import Foundation
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyProgressionInterface

/// Validates a requested perk against the tree, the chain and the record's own
/// conditions.
///
/// `@MainActor` only because reading ownership goes through `PerkRuntime`,
/// which writes to a main-actor store.
@MainActor
public struct PerkTreeSpendValidator {
    /// Ownership plus the load-order PERK index.
    public let runtime: PerkRuntime
    /// Where each perk sits in a skill tree.
    public let trees: PerkTreeIndex
    public let conditionRegistry: ConditionFunctionRegistry

    /// Depth cap for the walk back to a chain head, matching `PerkStore`'s own
    /// cap so a mod-authored `NNAM` loop cannot hang a click.
    private static let chainDepthCap = 32

    public init(
        runtime: PerkRuntime,
        trees: PerkTreeIndex,
        conditionRegistry: ConditionFunctionRegistry
    ) {
        self.runtime = runtime
        self.trees = trees
        self.conditionRegistry = conditionRegistry
    }

    /// Whether `holder` may spend a point on `perk` now: nil when allowed, else the
    /// refusing rule. The `perks` seam of `conditions` is rebuilt from live ownership,
    /// so a `HasPerk` prerequisite sees what the actor owns now.
    public func refusal(
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

    /// Whether the perk's own condition run holds. An empty run holds. A function
    /// OpenSky does not know holds, because the game answers every function and a
    /// mod's perk must not lock forever (docs/engine/perks.md).
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
        evaluator.unknownFunctionsHold = true
        return evaluator.evaluate(record.record.conditions).isTrue
    }
}
