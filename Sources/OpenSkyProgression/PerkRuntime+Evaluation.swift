// Evaluating an entry point against one actor's owned perks. Steps: the entry
// point index gives effects in priority order, unowned ones dropped; each PRKC
// tab runs against its `PerkConditionSubject`, and an unbound subject is skipped
// and counted; the rest go to `PerkEntryPointEvaluator`. The context's `perks`
// seam is rebuilt from world state, so `HasPerk` chains work.
// See docs/engine/perks.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface
import os

extension PerkRuntime {
    public static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Perks"
    )

    /// What `holder`'s perks do to `value` at `entryPoint`.
    ///
    /// An entry point nothing hooks, or one every hook is refused at, answers
    /// with the value it was handed. That is the identity rule the whole
    /// subsystem follows: an unimplemented entry point never zeroes a formula.
    @discardableResult
    public mutating func modify(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        subjects: PerkEvaluationSubjects? = nil,
        actorValue: (Int32) -> Float? = { _ in nil }
    ) -> PerkEntryPointOutcome {
        tally.noteEvaluation()
        let bound = subjects ?? PerkEvaluationSubjects(owner: holder.key)
        let outcome = PerkEntryPointEvaluator.evaluate(
            value,
            through: operands(at: entryPoint, on: holder, subjects: bound),
            actorValue: actorValue
        )
        for skip in outcome.skipped {
            // Once per distinct function, which is what the transition from
            // "never seen" to "seen" in the tally marks. A perk effect a
            // formula cannot carry out is a gap worth naming, and naming it per
            // evaluation would flood the log from inside a combat loop.
            if
                case let .unsupportedFunction(function) = skip,
                tally.unsupportedFunctions[function.description] == nil
            {
                let detail = "\(entryPoint.description) uses \(function.description), "
                    + "which produces no number; the value is left unchanged"
                Self.logger.warning("[WARNING] perk \(detail, privacy: .public)")
            }
            tally.note(skip)
        }
        return outcome
    }

    /// The multiplier form: `modify(1, ...)`. Combat folds perks in as a factor:
    /// `damage * (1 + perk effects) * (1 + item effects)` (UESP "Skyrim:Weapons").
    public mutating func multiplier(
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        subjects: PerkEvaluationSubjects? = nil,
        actorValue: (Int32) -> Float? = { _ in nil }
    ) -> Float {
        modify(1, at: entryPoint, on: holder, subjects: subjects, actorValue: actorValue).value
    }

    /// The owned, condition-passing effects hooking `entryPoint`, in the order
    /// the evaluator folds them.
    public mutating func operands(
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        subjects: PerkEvaluationSubjects
    ) -> [PerkEntryPointOperand] {
        let state = state(of: holder)
        guard !state.isEmpty else { return [] }
        var context = conditions
        let owned = ownership(of: subjects.boundReferences + [holder.key])
        var operands: [PerkEntryPointOperand] = []
        for match in perks.matches(at: entryPoint) {
            let key = ReferenceKey(resolved: match.perk)
            guard
                state.owns(key),
                let owner = perks.perk(match.perk),
                let effect = perks.effect(match)
            else { continue }
            // A condition's FormID parameter is spelled against the plugin that
            // authored the *record it was read from*, so the seam is rebuilt per
            // perk rather than once per evaluation: `HasPerk` in a patch's perk
            // names the patch's masters, not the base plugin's.
            context.perks = PerkConditionResolution(
                store: perks, sourcePlugin: owner.sourcePlugin, owned: owned
            )
            guard passes(effect.effect, at: entryPoint, subjects: subjects, context: &context)
            else { continue }
            guard case let .entryPoint(payload) = effect.effect.data else { continue }
            operands.append(PerkEntryPointOperand(
                function: payload.function,
                data: effect.effect.functionData,
                priority: match.priority
            ))
        }
        conditions.random = context.random
        return operands
    }

    // MARK: - Private

    /// Whether every condition tab this engine can bind a subject for holds.
    private mutating func passes(
        _ effect: PerkEffect,
        at entryPoint: PerkEntryPoint,
        subjects: PerkEvaluationSubjects,
        context: inout ConditionContext
    ) -> Bool {
        for tab in effect.conditionTabs where !tab.conditions.conditions.isEmpty {
            // The PRKC byte is the index into this entry point's documented
            // condition-type list, not a run-on type. `Armsman00` reads
            // "tab 0 (run on 0)" for its perk-owner tab and "tab 1 (run on 1)"
            // for its weapon tab, and `Mod Attack Damage` documents
            // (Perk Owner, Weapon, Target) in that order.
            let subject = entryPoint.conditionSubject(atTab: Int(tab.runOn)) ?? .perkOwner
            guard let reference = subjects[subject] else {
                tally.noteUnboundSubject(subject)
                continue
            }
            context.subject = reference
            context.target = subjects[.target] ?? reference
            var evaluator = ConditionEvaluator(
                context: context, registry: conditionRegistry
            )
            let outcome = evaluator.evaluate(tab.conditions)
            context.random = evaluator.context.random
            guard outcome.isTrue else {
                tally.noteConditionFailed()
                return false
            }
        }
        return true
    }
}
