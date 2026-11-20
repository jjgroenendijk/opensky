// The System page's Controls list: one row per remappable gameplay action, named by
// the key name table, and the calls the page makes by name.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
@testable import OpenSkyMenus
import OpenSkyMenusInterface
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

    /// The movie sorts and draws the list in the same script as its request, so the
    /// rows must be in it when the call returns. Other calls wait in the queue.
    @MainActor
    @Test func controlsRowsFillTheListDuringTheRequest() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        var queued: [SystemMenuMovieBridge.Request] = []
        SystemMenuMovieBridge.registerCalls(
            runtime: runtime,
            mappings: {
                [.init(text: "Forward", sortIndex: 0, buttonName: "W", buttonID: 0x11)]
            },
            onCall: { queued.append($0.request) }
        )
        let list = runtime.runtime.makeArray([])
        _ = runtime.callHost("RequestInputMappings", arguments: [.object(list)])
        let row = list.lookup("0")?.property.value.objectValue
        #expect(row?.lookup("text")?.property.value == .string("Forward"))
        #expect(queued.isEmpty)
        _ = runtime.callHost("SAVE", arguments: [])
        #expect(queued == [.saveList])
        #expect(SystemMenuMovieBridge.mappingListPath.hasSuffix("InputMappingPanel/List_mc"))
    }

    @MainActor
    @Test func theProbeAnswersControlsWithTheDefaultBindings() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        SystemMenuMovieBridge.registerDefaultCalls(runtime: runtime)
        let list = runtime.runtime.makeArray([])
        _ = runtime.callHost("RequestInputMappings", arguments: [.object(list)])
        #expect(list.lookup("0")?.property.value.objectValue != nil)
        #expect(SystemMenuMovieBridge.shownMappingRows(runtime: runtime) == 0, "no list clip")
    }

    /// `SystemPage.handleInput` goes back on `NavigationCode.TAB` and ignores `ESCAPE`.
    @Test func cancelReachesThePagesAsTab() {
        #expect(SystemMenuMovieBridge.pageKey(.button(.cancel))?.code == SWFKeyCode.tab)
        #expect(SystemMenuMovieBridge.pageKey(.button(.xButton))?.code == 88)
        #expect(SystemMenuMovieBridge.pageKey(.move(.down)) == nil)
    }
}
