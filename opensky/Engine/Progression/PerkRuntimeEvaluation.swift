// Evaluating an entry point against one actor's owned perks (issue #497,
// roadmap item 20.4): the half of the perk runtime a combat or magic formula
// actually calls.
//
// A satellite of `PerkRuntime` so that type stays under the strict-lint file
// cap, and along a real seam: everything there is ownership — who has which
// perk — and everything here is a number a formula asked about.
//
// ## The three steps, and what each one refuses
//
// 1. `PerkStore`'s entry-point index answers which effects in the load order
//    hook the entry point at all, already in priority order. Effects belonging
//    to a perk the actor does not own are dropped here, which is the only
//    ownership test in the path.
// 2. Each surviving effect's PRKC condition tabs are evaluated. A tab is run
//    against the object its PRKC index names for this entry point
//    (`PerkConditionSubject`), so a "Weapon" tab is asked about the weapon and
//    not about the actor. A tab the caller bound no reference for is *skipped
//    and counted* rather than failed: failing it would make every vanilla
//    damage perk inert, because their weapon-type tabs name an object this
//    engine has no world reference for. That is a documented
//    over-application, and `PerkRuntimeTally.unboundConditionSubjects` is how
//    much of it happened.
// 3. What is left becomes operands for `PerkEntryPointEvaluator`, which is
//    where the arithmetic and the ordering live.
//
// ## Why the condition context is rebuilt here
//
// `HasPerk` is what makes a rank chain work — `Armsman00` carries
// `HasPerk Armsman20 == 0` — so the perk seam on the context has to reflect
// what the store holds *now*, not whatever the caller last published. Every
// evaluation therefore overwrites `ConditionContext.perks` from the world state
// for the actors involved, and leaves every other seam the caller supplied
// alone.
//
// Documented in docs/engine/perks.md.

import Foundation
import os

/// Which world reference each condition-tab subject is, for one evaluation.
///
/// The caller binds what it knows. A melee formula knows the perk owner and the
/// target; nothing in this engine can bind `weapon`, `item` or `enchantment`,
/// because those name inventory records rather than placed references.
nonisolated struct PerkEvaluationSubjects: Equatable, Sendable {
    private var references: [PerkConditionSubject: ReferenceKey]

    init(
        owner: ReferenceKey,
        target: ReferenceKey? = nil,
        attacker: ReferenceKey? = nil
    ) {
        references = [.perkOwner: owner]
        references[.target] = target
        references[.attacker] = attacker
    }

    subscript(subject: PerkConditionSubject) -> ReferenceKey? {
        references[subject]
    }

    var owner: ReferenceKey? {
        references[.perkOwner]
    }

    /// Every bound reference, which is what the condition seam is built for.
    var boundReferences: [ReferenceKey] {
        Array(Set(references.values))
    }
}

extension PerkRuntime {
    static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Perks"
    )

    /// What `holder`'s perks do to `value` at `entryPoint`.
    ///
    /// An entry point nothing hooks, or one every hook is refused at, answers
    /// with the value it was handed. That is the identity rule the whole
    /// subsystem follows: an unimplemented entry point never zeroes a formula.
    @discardableResult
    mutating func modify(
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

    /// The multiplier form: `modify(1, ...)`.
    ///
    /// Every combat surface this wires into folds perks in as a factor beside
    /// the fortify term — `damage * (1 + perk effects) * (1 + item effects)`,
    /// UESP "Skyrim:Weapons" — and a vanilla damage perk is authored as
    /// `Multiply Value 1.2` on `Mod Attack Damage`, so evaluating the identity
    /// element is exactly the factor those formulas want.
    mutating func multiplier(
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        subjects: PerkEvaluationSubjects? = nil,
        actorValue: (Int32) -> Float? = { _ in nil }
    ) -> Float {
        modify(1, at: entryPoint, on: holder, subjects: subjects, actorValue: actorValue).value
    }

    /// The owned, condition-passing effects hooking `entryPoint`, in the order
    /// the evaluator folds them.
    mutating func operands(
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
                priority: match.priority,
                perk: key
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
