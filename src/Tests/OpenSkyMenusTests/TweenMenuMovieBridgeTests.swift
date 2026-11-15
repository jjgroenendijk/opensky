// The Tween movie contract on a synthetic root: the calls the engine makes on open and
// close, and the movie's calls back.

import Foundation
import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
struct TweenMenuMovieBridgeTests {
    private static func rootCalls(_ runtime: SWFMovieRuntime) -> MenuMovieEventLog<String> {
        let calls = MenuMovieEventLog<String>()
        for name in ["InitExtensions", "ShowMenu", "StartOpenMenuAnim", "StartCloseMenuAnim"] {
            AS2Runtime.method(runtime.runtime, on: runtime.root.object, name: name) { context in
                let detail = context.arguments.map { "\($0)" }.joined(separator: ",")
                calls.append(detail.isEmpty ? name : "\(name)(\(detail))")
                return .undefined
            }
        }
        return calls
    }

    @Test func openFillsTheBarAndCloseStartsTheAnimation() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let calls = Self.rootCalls(runtime)
        let content = TweenMenuContent(
            date: "Sundas", level: 7, levelProgress: 1.5, levelUpReady: true
        )
        TweenMenuMovieBridge.activate(runtime: runtime, content: content)
        TweenMenuMovieBridge.startClose(runtime: runtime)
        #expect(calls.events.count == 4)
        #expect(calls.events.first == "InitExtensions")
        #expect(calls.events[2].hasPrefix("StartOpenMenuAnim("))
        #expect(calls.events[2].contains("100"), "the progress is clamped to 100")
        #expect(calls.events.last == "StartCloseMenuAnim")
    }

    @Test func theMovieCallsBackWithTheEntryNumber() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let events = MenuMovieEventLog<TweenMovieEvent>()
        TweenMenuMovieBridge.prepare(runtime: runtime) { events.append($0) }
        runtime.callHost("HighlightMenu", arguments: [.number(2)])
        runtime.callHost("OpenHighlightedMenu", arguments: [.number(4)])
        runtime.callHost("OpenHighlightedMenu", arguments: [.number(9)])
        runtime.callHost("OpenAnimFinished", arguments: [])
        runtime.callHost("StartCloseMenu", arguments: [])
        runtime.callHost("CloseMenu", arguments: [])
        #expect(events.events == [.highlight(.magic), .open(.map), .closing, .closed])
    }
}
