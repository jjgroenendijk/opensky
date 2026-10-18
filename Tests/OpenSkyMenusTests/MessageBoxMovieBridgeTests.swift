// The message box movie bridge: what the engine sends for one box, and the
// button the movie reports.

import Foundation
import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import Testing

@MainActor
struct MessageBoxMovieBridgeTests {
    @Test func aBoxSendsItsTextButtonsAndCancelRule() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let log = MenuMovieCallLog(runtime: runtime, names: [
            "setMessageText", "setIsVertical", "setIsCancellable", "setButtons"
        ])
        let request = MessageBoxRequest(
            title: "Stone",
            text: "Take the blessing?",
            buttons: [
                MessageBoxButton(index: 0, text: "Yes"), MessageBoxButton(index: 2, text: "No")
            ],
            token: 7
        )
        MessageBoxMovieBridge.publish(request, runtime: runtime)
        #expect(log.names == ["setMessageText", "setIsVertical", "setIsCancellable", "setButtons"])
        let text = log.arguments(of: "setMessageText")?.first
        #expect(text == .string("Stone\n\nTake the blessing?"))
        #expect(log.arguments(of: "setIsCancellable")?.first == .boolean(false))
        #expect(log.arguments(of: "setButtons") == [.boolean(true), .string("Yes"), .string("No")])
    }

    @Test func aClickedButtonReportsItsRow() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let rows = MenuMovieEventLog<Int>()
        MessageBoxMovieBridge.prepare(runtime: runtime) { rows.append($0) }
        runtime.callHost("buttonPress", arguments: [.number(1)])
        runtime.callHost("buttonPress", arguments: [.string("x")])
        #expect(rows.events == [1])
    }
}
