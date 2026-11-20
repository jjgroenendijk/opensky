// The journal's bottom bar gets the date and the level through `SetPlayerInfo`.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
@testable import OpenSkyMenus
import Testing

@MainActor
struct JournalBottomBarTests {
    private final class Source: JournalBottomBarSource {
        var gameDateText: String?
        var tweenLevel = TweenMenuLevel(level: 7, progress: 1.5, levelUpReady: false)
    }

    @Test func theBarGetsTheDateTheLevelAndAClampedPercent() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        var parent = runtime.root
        for name in SystemMenuMovieBridge.bottomBarPath.split(separator: "/") {
            let child = SWFDisplayObject(content: .clip(nil))
            child.name = String(name)
            parent.addChild(child, atDepth: 1)
            parent = child
        }
        let bar = parent.object
        var received: [AS2Value] = []
        AS2Runtime.method(runtime.runtime, on: bar, name: "SetPlayerInfo") { context in
            received = context.arguments
            return .undefined
        }
        let source = Source()
        SystemMenuMovieBridge.showPlayerInfo(from: source, runtime: runtime)
        #expect(received.isEmpty, "no date, no game")
        source.gameDateText = "Sundas, 8:00 AM"
        SystemMenuMovieBridge.showPlayerInfo(from: source, runtime: runtime)
        #expect(received == [.string("Sundas, 8:00 AM"), .integer(7), .number(100)])
    }
}
