// The System page's Controls list: one row per remappable gameplay action, named by
// the key name table, and the calls the page makes by name.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
@testable import OpenSkyMenus
import Testing

struct SystemMenuMovieCallsTests {
    @Test func mappingRowsNameEachRemappableGameplayKey() {
        let rows = SystemMenuMovieBridge.mappingRows(InputBindings()) { code in
            code == 0x11 ? "W" : "Key \(code)"
        }
        let forward = rows.first { $0["text"] == .string("Forward") }
        #expect(forward?["buttonName"] == .string("W"))
        #expect(forward?["buttonID"] == .integer(0x11))
        #expect(!rows.contains { $0["text"] == .string("Accept") }, "menu keys are not listed")
        let order = rows.compactMap { row -> Double? in
            if case let .number(index)? = row["sortIndex"] {
                index
            } else {
                nil
            }
        }
        #expect(order == order.sorted())
    }

    @Test func requestsUseTheMovieNames() {
        #expect(SystemMenuMovieBridge.Request.saveList.rawValue == "SAVE")
        #expect(SystemMenuMovieBridge.Request.startRemap.rawValue == "StartRemapMode")
        #expect(!SystemMenuMovieBridge.quietRequests.contains("SAVE"))
    }

    @Test func theQuitRowLearnsItRunsOnPC() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        SystemMenuMovieBridge.prepare(runtime: runtime)
        #expect(runtime.callHost("RequestIsOnPC", arguments: []) == .boolean(true))
    }

    /// `SystemPage.handleInput` goes back on `NavigationCode.TAB` and ignores `ESCAPE`.
    @Test func cancelReachesThePagesAsTab() {
        #expect(SystemMenuMovieBridge.pageKey(.button(.cancel))?.code == SWFKeyCode.tab)
        #expect(SystemMenuMovieBridge.pageKey(.button(.xButton))?.code == 88)
        #expect(SystemMenuMovieBridge.pageKey(.move(.down)) == nil)
    }
}
