// What Play does for each mix of the launch options and saves.

import OpenSkyLaunch
import Testing

struct LaunchPlanTests {
    private let cell = LaunchStart.cell("WhiterunBanneredMare")

    @Test func resumeAndSkipLoadTheNewestSave() {
        let plan = LaunchPlan(
            resumesLatestSave: true, skipsMainMenu: true, newestSlot: "quick", start: cell
        )
        #expect(plan == .resume(slot: "quick"))
        #expect(plan.start == .normal)
    }

    @Test func resumeWithoutSkipOpensTheMainMenu() {
        let plan = LaunchPlan(
            resumesLatestSave: true, skipsMainMenu: false, newestSlot: "quick", start: cell
        )
        #expect(plan == .mainMenu)
    }

    @Test func resumeWithoutASaveStartsANewGame() {
        let plan = LaunchPlan(
            resumesLatestSave: true, skipsMainMenu: true, newestSlot: nil, start: cell
        )
        #expect(plan == .newGame(cell))
        #expect(plan.start == cell)
    }

    @Test func withoutResumeTheNewGameStartDecides() {
        #expect(LaunchPlan(
            resumesLatestSave: false, skipsMainMenu: true, newestSlot: "quick", start: .normal
        ) == .mainMenu)
        #expect(LaunchPlan(
            resumesLatestSave: false, skipsMainMenu: true, newestSlot: "quick", start: cell
        ) == .newGame(cell))
    }
}
