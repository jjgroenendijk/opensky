// Focus-path filtering for the menu-handler route (issue #229).
//
// Split out of `SWFRuntimeInputTests` so that suite stays under the type-body
// limit. Device-free, synthetic fixtures only — no test reads a real `.swf`
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct SWFRuntimeFocusPathTests {
    /// Three nested clips — `menuRoot` -> `holder` -> `child` — so a focus path
    /// between `menuRoot` and a focused `child` must cross the `holder`. This is
    /// the `startmenu.swf` shape (`Menu_mc` -> `MainListHolder` -> `List_mc`),
    /// reduced to the smallest form that exercises the holder-clip filter.
    private static func nestedHandlerTags() -> [SWFFixture.Tag] {
        [
            SWFRuntimeFixture.rectangle(id: 1, width: 1000, height: 1000),
            // `child`: a rectangle inside a sprite.
            SWFDisplayFixture.spriteTag(characterId: 2, frameCount: 1, tags: [
                SWFRuntimeFixture.place(1, depth: 1), SWFDisplayFixture.showFrameTag
            ]),
            // `holder`: places `child`. Defines no `handleInput`.
            SWFDisplayFixture.spriteTag(characterId: 3, frameCount: 1, tags: [
                SWFRuntimeFixture.place(2, depth: 1, name: "child"),
                SWFDisplayFixture.showFrameTag
            ]),
            // `menuRoot`: places `holder`. `handleInput` is recorded after start.
            SWFDisplayFixture.spriteTag(characterId: 4, frameCount: 1, tags: [
                SWFRuntimeFixture.place(3, depth: 1, name: "holder"),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFRuntimeFixture.place(4, depth: 1, name: "menuRoot"),
            SWFDisplayFixture.showFrameTag
        ]
    }

    /// The focus path handed to the menu handler carries only clips that define
    /// `handleInput`. Vanilla nests a list under a plain holder clip
    /// (`startmenu.swf`: `MainListHolder` between `Menu_mc` and `List_mc`); the
    /// movie's own routing forwards down `pathToFocus[0]`, so an unfiltered path
    /// hands it a clip that defines none and the key is dropped (issue #229).
    @Test func theFocusPathDropsHolderClipsWithoutHandleInput() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.nestedHandlerTags())
        let menuRoot = try #require(runtime.root.child(named: "menuRoot"))
        let holder = try #require(menuRoot.child(named: "holder"))
        let child = try #require(holder.child(named: "child"))

        var receivedPath: [String] = []
        AS2Natives.method(runtime.runtime, on: menuRoot.object, name: "handleInput") { context in
            receivedPath = context.argument(1).objectValue?.elements.compactMap {
                SWFDisplayObject.resolve($0.objectValue)?.name
            } ?? []
            return .boolean(true)
        }
        // `child` defines `handleInput`, so the filter keeps it; `holder`
        // defines none, so the filter drops it.
        AS2Natives.method(runtime.runtime, on: child.object, name: "handleInput") { _ in
            .boolean(true)
        }

        #expect(runtime.menuInputHandler === menuRoot)
        #expect(runtime.setFocus(.object(child.object)))
        // The raw chain still crosses the holder, which is what the filter must
        // remove before the movie sees the path.
        #expect(runtime.focusChain(under: menuRoot).map(\.name) == ["holder", "child"])

        #expect(runtime.handle(.keyDown(code: SWFKeyCode.down, ascii: 0)))
        #expect(receivedPath == ["child"])
    }
}
