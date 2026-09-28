// M13 acceptance, budget half (issue #185): quest script execution and quest
// condition evaluation are held to the budgets that already exist, and add no
// mechanism of their own.
//
// Two budgets, both already shipping. Stage fragments go through the same
// per-tick FIFO every other script event uses, so `PapyrusTickBudget` bounds
// them without anything being taught about quests. Quest conditions are pure
// reads of `QuestResolution` and execute no bytecode at all, so the per-frame
// script update budget the fly-path validator enforces cannot be moved by them
// — which is asserted here rather than assumed, because "it is free" is exactly
// the kind of claim that stops being true quietly.
//
// The timings are synthetic, as they are throughout `CellStreamingFlyPathTests`:
// these cases pin the gate's behaviour, not this machine's speed. Measured
// timings against the real install come from `openskycli bench --fly-path`.

import Foundation
@testable import opensky
import Testing

@MainActor
struct M13AcceptanceBudgetTests {
    /// More fragments on one stage than a tick may dispatch, so the carry-over
    /// is real rather than theoretical.
    private static let fragmentCount = 40

    // MARK: - Script execution

    /// A stage carrying more fragments than the per-tick event budget allows
    /// dispatches exactly the budget and carries the rest, in table order.
    ///
    /// This is the whole claim: nothing about quests bypasses the FIFO, so the
    /// VM's existing bound is the quest's bound.
    @Test
    func stageFragmentsObeyThePerTickEventBudget() throws {
        let session = try Self.busyStageSession()
        PapyrusWorldFixture.drain(session.world)
        #expect(session.world.budget == .standard)

        try session.bridge.setQuestStage(
            PapyrusQuestFixture.fragmentStage, for: PapyrusQuestFixture.questKey
        )
        #expect(session.world.eventQueue.count == Self.fragmentCount)

        let first = session.world.stepFixed()
        #expect(first.dispatched == PapyrusTickBudget.standard.events)
        #expect(first.queued == Self.fragmentCount - PapyrusTickBudget.standard.events)
        #expect(first.faulted == 0)

        // The carry-over drains on the following ticks, in the order the
        // fragment table listed the functions.
        PapyrusWorldFixture.drain(session.world)
        #expect(session.world.eventQueue.isEmpty)
        #expect(
            session.dispatch.notes.suffix(Self.fragmentCount)
                == (0 ..< Self.fragmentCount).map { "fragment.\($0)" }
        )
        #expect(session.world.runtime.tally.faultTotal == 0)
    }

    /// The same run's instruction spend stays inside the per-tick instruction
    /// budget, which is the other half of `PapyrusTickBudget` and the one a
    /// long fragment body would breach first.
    @Test
    func stageFragmentsStayInsideThePerTickInstructionBudget() throws {
        let session = try Self.busyStageSession()
        PapyrusWorldFixture.drain(session.world)
        let floor = session.world.runtime.tally.instructionsExecuted

        try session.bridge.setQuestStage(
            PapyrusQuestFixture.fragmentStage, for: PapyrusQuestFixture.questKey
        )
        session.world.stepFixed()
        let spent = session.world.runtime.tally.instructionsExecuted - floor
        #expect(spent > 0, "the tick dispatched fragments but executed nothing")
        #expect(spent < PapyrusTickBudget.standard.instructions)
    }

    // MARK: - Condition evaluation

    /// Quest conditions cost the script VM nothing: they are reads of the quest
    /// seam on `ConditionContext`, not bytecode, so a frame full of them cannot
    /// move the script update budget.
    @Test
    func questConditionEvaluationExecutesNoBytecode() throws {
        let session = try Self.busyStageSession()
        PapyrusWorldFixture.drain(session.world)
        try session.bridge.setQuestStage(
            PapyrusQuestFixture.fragmentStage, for: PapyrusQuestFixture.questKey
        )
        PapyrusWorldFixture.drain(session.world)

        let runtime = try #require(session.bridge.questRuntime)
        let context = ConditionContext(quests: runtime.resolution())
        var evaluator = ConditionEvaluator(context: context)
        let floor = session.world.runtime.tally.instructionsExecuted

        // Every quest condition function issue #182 registered, evaluated over
        // the quest the fragments just advanced.
        for index in [56, 58, 59, 543] {
            let outcome = try evaluator.evaluate(
                Self.questCondition(functionIndex: UInt16(index))
            )
            #expect(outcome.isConclusive, "condition \(index) could not be answered")
        }
        #expect(session.world.runtime.tally.instructionsExecuted == floor)
        #expect(evaluator.tally.conditionsEvaluated == 4)
        #expect(evaluator.tally.unresolvedQuestTotal == 0)
    }

    // MARK: - Frame budgets

    /// The shipping fly-path update budgets over a frame whose script time is
    /// the quest work above: the gate passes inside budget and still refuses an
    /// over-budget run, so it is live rather than vacuous.
    ///
    /// The validator and the configuration are the ones
    /// `openskycli bench --fly-path` uses, so no second set of numbers is kept
    /// in step — which is what the issue's "extend them" means to avoid.
    @Test
    func questDrivenFramesStayWithinTheShippingUpdateBudgets() throws {
        let inBudget = OffscreenBenchResult(
            frameMS: [8, 9, 8],
            windowSummaries: [],
            animationMS: [1, 1, 1],
            shadowMS: [0.4, 0.5, 0.4],
            audioUpdateMS: [0.1, 0.1, 0.1],
            scriptUpdateMS: [0.2, 0.3, 0.2]
        )
        try validatedFlyUpdateBudgets(
            render: inBudget, configuration: Self.configuration()
        )
        #expect(inBudget.scriptUpdatePercentileMS(95) <= 0.5)

        let overBudget = OffscreenBenchResult(
            frameMS: [8, 9, 8],
            windowSummaries: [],
            animationMS: [1, 1, 1],
            shadowMS: [0.4, 0.5, 0.4],
            audioUpdateMS: [0.1, 0.1, 0.1],
            scriptUpdateMS: [1, 2, 3]
        )
        #expect(throws: CellStreamingFlyBenchmarkError.self) {
            try validatedFlyUpdateBudgets(
                render: overBudget, configuration: Self.configuration()
            )
        }
    }

    // MARK: - Fixtures

    /// A quest whose one stage carries `fragmentCount` fragments, each a
    /// distinct function on the generated fragment script.
    private static func busyStageSession() throws -> PapyrusWorldFixture.Session {
        let fragments = (0 ..< fragmentCount).map { index in
            QuestFixture.Fragment(
                stage: PapyrusQuestFixture.fragmentStage,
                logEntry: Int32(index),
                script: PapyrusQuestFixture.fragmentScript,
                function: "Fragment_\(index)"
            )
        }
        let functions = (0 ..< fragmentCount).map { index in
            (
                "Fragment_\(index)",
                PapyrusWorldFixture.probeBody(note: "fragment.\(index)")
            )
        }
        return try PapyrusQuestFixture.session(
            quest: PapyrusQuestFixture.quest(fragments: fragments),
            objects: PapyrusQuestFixture.objects(fragmentFunctions: functions)
        )
    }

    /// One condition calling `functionIndex` on the fixture's quest, compared
    /// against zero — the comparison does not matter here, only that the
    /// function is answered.
    private static func questCondition(functionIndex: UInt16) throws -> Condition {
        try ConditionEvaluatorFixture.condition(
            functionIndex: functionIndex,
            parameter1: PapyrusQuestFixture.questObjectID
        )
    }

    /// The shipping fly-path budgets, matching `openskycli bench --fly-path`'s
    /// own defaults, spelled the way `M12AcceptanceBudgetTests` spells them
    /// because they are private to the command.
    private static func configuration() -> CellStreamingFlyBenchmarkConfiguration {
        CellStreamingFlyBenchmarkConfiguration(
            start: CellCoordinate(x: 0, y: 0),
            size: (width: 1, height: 1),
            maxFrames: 1,
            footprintCapMB: 1024,
            collisionBuildBudgetMS: 750,
            actorBuildBudgetMS: 3000,
            animationUpdateBudgetMS: 4,
            shadowUpdateBudgetMS: 1.5,
            audioUpdateBudgetMS: 0.5,
            scriptUpdateBudgetMS: 0.5
        )
    }
}
