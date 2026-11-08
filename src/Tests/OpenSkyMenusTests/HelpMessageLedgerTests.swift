// `ShowAsHelpMessage`: duration, interval, the max-times limit, the event
// that ends the message, and `ResetHelpMessage`.

@testable import OpenSkyMenus
import OpenSkyScriptingInterface
import Testing

struct HelpMessageLedgerTests {
    @Test func showsHidesAndShowsAgainUntilTheLimit() {
        var ledger = HelpMessageLedger()
        let shown = ledger.show(
            event: "Jump",
            text: "Press Jump",
            duration: 5,
            interval: 30,
            maxTimes: 2
        )
        #expect(shown)
        let changed = ledger.advance(to: 0)
        #expect(changed)
        #expect(ledger.visibleText == "Press Jump")
        let changed2 = ledger.advance(to: 5)
        #expect(changed2)
        #expect(ledger.visibleText == nil)
        let changed3 = ledger.advance(to: 20)
        #expect(!changed3)
        let changed4 = ledger.advance(to: 35)
        #expect(changed4)
        #expect(ledger.records["jump"]?.timesShown == 2)
        _ = ledger.advance(to: 40)
        _ = ledger.advance(to: 80)
        #expect(ledger.active == nil)
        let shown2 = ledger.show(
            event: "jump",
            text: "Press Jump",
            duration: 5,
            interval: 30,
            maxTimes: 2
        )
        #expect(!shown2)
    }

    @Test func theEventEndsTheMessageForGood() {
        var ledger = HelpMessageLedger()
        ledger.show(event: "Sneak", text: "Press Sneak", duration: 0, interval: 0, maxTimes: 0)
        _ = ledger.advance(to: 0)
        _ = ledger.advance(to: 100)
        #expect(ledger.visibleText == "Press Sneak")
        ledger.noteEvent("SNEAK")
        #expect(ledger.visibleText == nil)
        #expect(ledger.records["sneak"]?.isDone == true)
        let shown = ledger.show(
            event: "Sneak",
            text: "Press Sneak",
            duration: 0,
            interval: 0,
            maxTimes: 0
        )
        #expect(!shown)
    }

    @Test func resetAllowsTheEventAgain() {
        var ledger = HelpMessageLedger(records: ["sneak": HelpMessageRecord(
            timesShown: 3,
            isDone: true
        )])
        ledger.reset(event: "Sneak")
        #expect(ledger.records["sneak"] == nil)
        let shown = ledger.show(
            event: "Sneak",
            text: "Press Sneak",
            duration: 1,
            interval: 1,
            maxTimes: 1
        )
        #expect(shown)
    }

    @Test func eventWithNoMessageIsNotRecorded() {
        var ledger = HelpMessageLedger()
        ledger.noteEvent("Jump")
        #expect(ledger.records.isEmpty)
    }
}
