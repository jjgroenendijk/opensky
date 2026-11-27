import OpenSkyScripting
import Testing

struct HeadlessSweepReportTests {
    @Test func ranksProblemsBySubjectsStoppedAndCountsEachPairOnceInAnyCase() {
        var report = HeadlessSweepReport()
        for _ in 0 ..< 3 {
            report.noteRun()
        }
        report.note("alias does not fill", subject: "QuestA")
        report.note("alias does not fill", subject: "QuestB")
        report.note("alias does not fill", subject: "QuestA")
        report.note("scene cannot start", subject: "QuestB")
        report.note("Alias does not fill", subject: "QuestC")

        #expect(report.ranked(examples: 1) == [
            .init(problem: "alias does not fill", examples: ["QuestA"], count: 3),
            .init(problem: "scene cannot start", examples: ["QuestB"], count: 1)
        ])
        #expect(report.failed == 3)
        #expect(report.text(unit: "quests", limit: 1, examples: 2) == """
        3 quests run, 3 with a problem, 2 problems
        3\talias does not fill\tQuestA, QuestB

        """)
    }

    @Test func deltaNamesOnlyTheFallbacksThatRose() {
        let before = ["fault typeMismatch": 2, "stubbed native Game.UsingGamepad": 1]
        let after = ["fault typeMismatch": 2, "stubbed native Game.UsingGamepad": 3, "new": 1]

        #expect(HeadlessSweepReport.delta(before: before, after: after)
            == ["new", "stubbed native Game.UsingGamepad"])
    }

    @Test func fragmentProblemsGroupTheFallbackNames() {
        #expect(HeadlessSweepReport.fragmentProblem("None from native Game.GetPlayer")
            == "native returns None: Game.GetPlayer")
        #expect(HeadlessSweepReport.fragmentProblem("property binding skip unresolved form")
            == "property does not resolve: unresolved form")
        #expect(HeadlessSweepReport.fragmentProblem("fault missingFunction")
            == "runtime error: missingFunction")
        #expect(HeadlessSweepReport.fragmentProblem("other") == "other")
        #expect(HeadlessSweepReport
            .fragmentProblem("script skip event function not defined") == nil)
    }

    @Test func fallbackTableListsTheMostCountedFirst() {
        #expect(HeadlessSweepReport.fallbackTable([("b", 1), ("a", 1), ("c", 5)])
            == "c\t5\na\t1\nb\t1\n")
    }
}
