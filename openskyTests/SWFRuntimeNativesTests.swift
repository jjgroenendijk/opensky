// `MovieClip`, `TextField`, `Stage`, and `Selection` (milestone 8.3.2 phase 2).
//
// These four were the head of the missing-API tally after the interpreter
// landed — `Selection` 179 hits, `MovieClip` 168, `TextField` 25, `Stage` 7 —
// so the first assertion here is simply that referencing them no longer counts
// as missing.

import Foundation
@testable import opensky
import Testing

struct SWFRuntimeNativesTests {
    private func started() throws -> SWFMovieRuntime {
        try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
    }

    private func call(
        _ runtime: SWFMovieRuntime,
        _ name: String,
        on node: SWFDisplayObject,
        _ arguments: [AS2Value] = []
    ) throws -> AS2Value {
        // Prototype chain first, then the host fallback — exactly the order
        // `AS2Interpreter.getMember` uses.
        let member = node.object.lookup(name)?.property.value ?? runtime.member(name, of: node)
        let function = try #require(member?.functionValue)
        return runtime.runtime.invoke(
            .object(function), thisValue: .object(node.object), arguments: arguments
        ).value
    }

    private func global(_ runtime: SWFMovieRuntime, _ name: String) throws -> AS2Object {
        try #require(runtime.runtime.globalValue(name).objectValue)
    }

    @Test func theDisplayClassesAreResolvableGlobals() throws {
        let runtime = try started()
        for name in ["MovieClip", "TextField", "Stage", "Selection"] {
            #expect(runtime.runtime.globalValue(name).objectValue != nil, "\(name) missing")
            #expect(runtime.tally.missingNames[name] == nil)
        }
    }

    /// A clip whose class `extends MovieClip` must land on our prototype, so
    /// the clip methods stay reachable from the subclass.
    @Test func movieClipPrototypeCarriesTheTimelineMethods() throws {
        let runtime = try started()
        let prototype = runtime.movieClipPrototype
        for name in ["play", "stop", "gotoAndPlay", "gotoAndStop", "attachMovie", "getDepth"] {
            #expect(prototype.lookup(name)?.property.value.functionValue != nil, "\(name) missing")
        }
    }

    // MARK: - MovieClip methods

    @Test func attachMovieInstantiatesAnExportedCharacter() throws {
        let runtime = try started()
        let attached = try call(
            runtime, "attachMovie", on: runtime.root,
            [.string("PanelClip"), .string("copy"), .number(20)]
        )
        let node = try #require(SWFDisplayObject.resolve(attached.objectValue))
        #expect(node.name == "copy")
        #expect(node.depth == 20)
        #expect(runtime.root.child(atDepth: 20) === node)
        // The registered class ran on the attached instance too.
        #expect(node.object.lookup("built")?.property.value == .number(1))
    }

    @Test func attachingAnUnknownLinkageNameIsTalliedNotFatal() throws {
        let runtime = try started()
        let result = try call(
            runtime, "attachMovie", on: runtime.root,
            [.string("NoSuchThing"), .string("x"), .number(5)]
        )
        #expect(result == .undefined)
        #expect(runtime.tally.missingNames["NoSuchThing"] == 1)
    }

    @Test func createEmptyMovieClipAndRemoveMovieClipRoundTrip() throws {
        let runtime = try started()
        let created = try call(
            runtime, "createEmptyMovieClip", on: runtime.root, [.string("holder"), .number(30)]
        )
        let node = try #require(SWFDisplayObject.resolve(created.objectValue))
        #expect(runtime.root.child(named: "holder") === node)
        _ = try call(runtime, "removeMovieClip", on: node)
        #expect(runtime.root.child(atDepth: 30) == nil)
    }

    @Test func depthQueriesAndSwapsUseTheLiveTree() throws {
        let runtime = try started()
        let panel = try #require(runtime.root.child(named: "panel"))
        #expect(try call(runtime, "getDepth", on: panel) == .number(1))
        #expect(try call(runtime, "getNextHighestDepth", on: runtime.root) == .number(2))
        _ = try call(runtime, "swapDepths", on: panel, [.number(9)])
        #expect(panel.depth == 9)
        #expect(runtime.root.child(atDepth: 1) == nil)
        let atDepth = try call(runtime, "getInstanceAtDepth", on: runtime.root, [.number(9)])
        #expect(atDepth.objectValue === panel.object)
    }

    @Test func hitTestUsesTheTransformedBoundingBox() throws {
        let runtime = try started()
        let panel = try #require(runtime.root.child(named: "panel"))
        // The panel covers 400..2400 x 300..1500 twips = 20..120 x 15..75 px.
        #expect(try call(runtime, "hitTest", on: panel, [.number(30), .number(20)]) ==
            .boolean(true))
        #expect(
            try call(runtime, "hitTest", on: panel, [.number(300), .number(20)]) == .boolean(false)
        )
    }

    // MARK: - Stage and Selection

    @Test func stageReportsTheMovieFrameSizeInPixels() throws {
        let runtime = try started()
        let stage = try global(runtime, "Stage")
        // SWFDisplayFixture builds an 8000 x 6000 twip frame = 400 x 300 px.
        #expect(stage.lookup("width")?.property.value == .number(400))
        #expect(stage.lookup("height")?.property.value == .number(300))
        #expect(stage.lookup("scaleMode")?.property.value == .string("noScale"))
    }

    @Test func selectionRecordsFocusWithoutImplementingIt() throws {
        let runtime = try started()
        let selection = try global(runtime, "Selection")
        let panel = try #require(runtime.root.child(named: "panel"))
        let setFocus = try #require(
            selection.lookup("setFocus")?.property.value.functionValue
        )
        let accepted = runtime.runtime.invoke(
            .object(setFocus),
            thisValue: .object(selection),
            arguments: [.object(panel.object)]
        ).value
        #expect(accepted == .boolean(true))
        #expect(runtime.focusTarget === panel)
        let getFocus = try #require(selection.lookup("getFocus")?.property.value.functionValue)
        let path = runtime.runtime.invoke(
            .object(getFocus), thisValue: .object(selection)
        ).value
        #expect(path == .string("/panel"))
    }

    @Test func selectionAcceptsAPathStringAndClearsOnNull() throws {
        let runtime = try started()
        #expect(runtime.setFocus(.string("/panel")))
        #expect(runtime.focusTarget != nil)
        #expect(runtime.setFocus(.null))
        #expect(runtime.focusTarget == nil)
        #expect(runtime.setFocus(.string("/nowhere")) == false)
        #expect(runtime.focusChanges == 2)
    }

    /// `addListener` is 36 hits in the vanilla install. Listeners are recorded
    /// so the name resolves; dispatching to them is phase 3.
    @Test func listenersAreRecordedOnStageAndSelection() throws {
        let runtime = try started()
        for name in ["Stage", "Selection"] {
            let object = try global(runtime, name)
            let add = try #require(object.lookup("addListener")?.property.value.functionValue)
            let listener = runtime.runtime.makeObject()
            let added = runtime.runtime.invoke(
                .object(add), thisValue: .object(object), arguments: [.object(listener)]
            ).value
            #expect(added == .boolean(true))
            let list = try #require(object.lookup("_listeners")?.property.value.objectValue)
            #expect(list.elements.count == 1)
            let remove = try #require(
                object.lookup("removeListener")?.property.value.functionValue
            )
            let removed = runtime.runtime.invoke(
                .object(remove), thisValue: .object(object), arguments: [.object(listener)]
            ).value
            #expect(removed == .boolean(true))
            #expect(list.elements.isEmpty)
        }
    }

    // MARK: - TextField

    @Test func setTextIsTheScaleformSpellingOfAssigningText() throws {
        var builder = SWFEditTextBodyBuilder()
        builder.characterId = 3
        builder.flags.hasText = true
        builder.initialText = "AB"
        let runtime = try SWFRuntimeFixture.started(tags: [
            SWFFixture.Tag(code: 37, body: builder.build()),
            SWFRuntimeFixture.place(3, depth: 1, name: "field"),
            SWFDisplayFixture.showFrameTag
        ])
        let field = try #require(runtime.root.child(named: "field"))
        _ = try call(runtime, "SetText", on: field, [.string("CD")])
        #expect(runtime.text(of: field) == "CD")
        _ = try call(runtime, "SetTextHTML", on: field, [.string("<b>EF</b>")])
        #expect(runtime.text(of: field) == "EF")
    }
}
