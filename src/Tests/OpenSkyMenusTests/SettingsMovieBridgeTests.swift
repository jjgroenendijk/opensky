// The Settings page's movie side over a synthetic runtime: the CLI's default rows,
// the rows the options list shows, and the answer to a save.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

@MainActor
struct SettingsMovieBridgeTests {
    /// Builds the clips down to `path` and returns the last one.
    private static func clips(_ path: String, in runtime: SWFMovieRuntime) -> SWFDisplayObject {
        var parent = runtime.root
        for name in path.split(separator: "/") {
            let node = SWFDisplayObject(content: .clip(nil))
            node.name = String(name)
            parent.addChild(node, atDepth: UInt16(parent.children.count + 1))
            parent = node
        }
        return parent
    }

    @Test func theDefaultsFillEveryCategory() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        SettingsMovieBridge.registerDefaults(runtime: runtime)
        for name in SettingsMovieBridge.requestNames.keys {
            let list = runtime.runtime.makeArray([])
            runtime.callHost(name, arguments: [.object(list)])
            #expect((list.arrayLength ?? 0) > 0, "\(name) added no rows")
        }
    }

    @Test func theShownRowsAreTheOptionIDsInRowOrder() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        #expect(SettingsMovieBridge.shownRows(runtime: runtime) == nil)
        let list = Self.clips(SettingsMovieBridge.optionsListPath, in: runtime)
        let rows = [3, 1].map { id -> AS2Value in
            let row = runtime.runtime.makeObject()
            row.assign(.integer(id), for: "ID")
            return .object(row)
        }
        list.object.assign(.object(runtime.runtime.makeArray(rows)), for: "EntriesA")
        list.object.assign(.integer(1), for: "iSelectedIndex")
        let shown = try #require(SettingsMovieBridge.shownRows(runtime: runtime))
        #expect(shown.ids == [3, 1])
        #expect(shown.selected == 1)
    }

    @Test func aSaveIsAnsweredOnTheSystemPage() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        let page = Self.clips(SystemMenuMovieBridge.systemPagePath, in: runtime)
        let log = runtime.runtime.makeObject()
        AS2Runtime.method(runtime.runtime, on: page.object, name: "onSettingsSaved") { _ in
            log.assign(.boolean(true), for: "called")
            return .undefined
        }
        SystemMenuMovieBridge.finishSaving(runtime: runtime)
        #expect(log.lookup("called")?.property.value == .boolean(true))
    }

    @Test func closingACategoryShowsTheCategoryList() {
        var page = SettingsPageModel(catalog: PlayerSettingsCatalog.vanilla)
        page.openCategory(.audio)
        #expect(!page.rows.isEmpty)
        page.closeCategory()
        #expect(page.rows.isEmpty)
        #expect(page.selectedCategory == .audio)
    }
}
