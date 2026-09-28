// Dialogue menu bridge coverage over a synthetic runtime (issue #205). No game
// movie or extracted asset is used; the named display objects, the list base's
// `EntriesA`/`iSelectedIndex` pair and the entry points the bridge drives are
// installed in code, in the shape `openskycli swf dialogue-menu` measured off
// the vanilla movie.
//
// What these pin is the bridge's half of the contract: the rows it writes, the
// order it writes them in, the selection it leaves behind, and the fact that a
// movie missing a piece degrades rather than crashes. Whether the *vanilla*
// movie still has that shape is the real-data gate's job.

import AppKit
@testable import opensky
import Testing

private final class DialogueCallLog: @unchecked Sendable {
    private(set) var calls: [String: [[AS2Value]]] = [:]

    func append(_ name: String, arguments: [AS2Value]) {
        calls[name, default: []].append(arguments)
    }

    func count(_ name: String) -> Int {
        calls[name]?.count ?? 0
    }
}

private struct DialogueHarness {
    let runtime: SWFMovieRuntime
    let menu: SWFDisplayObject
    let list: SWFDisplayObject
    let log: DialogueCallLog
}

@MainActor
struct DialogueMenuMovieBridgeTests {
    /// The instance entry points the bridge calls, plus the list methods.
    private static let menuEntryPoints = [
        "PopulateDialogueLists", "SetSpeakerName", "ShowDialogueText",
        "HideDialogueText", "ShowDialogueList", "SetPlatform", "InitExtensions"
    ]
    private static let listEntryPoints = ["InvalidateData", "ClearList", "UpdateList"]

    private func makeRuntime(withMenuClass: Bool = true) throws -> DialogueHarness {
        let runtime = try SWFRuntimeFixture.started(tags: [
            SWFDisplayFixture.showFrameTag
        ])
        let log = DialogueCallLog()
        let menu = SWFDisplayObject(content: .clip(nil))
        menu.name = "DialogueMenu_mc"
        runtime.root.addChild(menu, atDepth: 1)
        let holder = SWFDisplayObject(content: .clip(nil))
        holder.name = "TopicListHolder"
        menu.addChild(holder, atDepth: 1)
        let list = SWFDisplayObject(content: .clip(nil))
        list.name = "List_mc"
        holder.addChild(list, atDepth: 1)
        list.object.define(.integer(-1), for: "iSelectedIndex")
        for name in ["SpeakerName", "SubtitleText"] {
            let field = SWFDisplayObject(content: .clip(nil))
            field.name = name
            menu.addChild(field, atDepth: name == "SpeakerName" ? 2 : 3)
        }
        for name in Self.menuEntryPoints {
            AS2Natives.method(runtime.runtime, on: menu.object, name: name) { context in
                log.append(name, arguments: context.arguments)
                return .undefined
            }
        }
        for name in Self.listEntryPoints {
            AS2Natives.method(runtime.runtime, on: list.object, name: name) { context in
                log.append(name, arguments: context.arguments)
                return .undefined
            }
        }
        if withMenuClass {
            try installMenuClass(runtime: runtime)
        }
        return DialogueHarness(runtime: runtime, menu: menu, list: list, log: log)
    }

    /// The movie's own state vocabulary, registered under the name the bridge
    /// reads it off, with the values measured on the vanilla class.
    private func installMenuClass(runtime: SWFMovieRuntime) throws {
        let menuClass = runtime.runtime.makeObject()
        for (index, name) in DialogueMenuMovieBridge.stateConstantNames.enumerated() {
            menuClass.assign(.integer(index), for: name)
        }
        _ = runtime.runtime.registerClass(
            symbol: DialogueMenuMovieBridge.menuClassName, constructor: menuClass
        )
    }

    private func model(_ texts: [String], selected: Int = 0) -> DialogueMenuModel {
        DialogueMenuModel(
            speaker: "Belethor",
            speakerKey: nil,
            topics: texts.enumerated().map { index, text in
                DialogueTopicEntry(
                    topic: FormID(UInt32(index + 1)),
                    info: FormID(UInt32(index + 0x100)),
                    text: text,
                    endsConversation: false
                )
            },
            selectedIndex: selected
        )
    }

    // MARK: - Rows

    @Test
    func publishesRowsSpeakerAndSelection() throws {
        let harness = try makeRuntime()
        DialogueMenuMovieBridge.publish(
            model(["Ask about the shop", "Never mind"], selected: 1),
            runtime: harness.runtime
        )
        #expect(
            DialogueMenuMovieBridge.topicLabels(runtime: harness.runtime)
                == ["Ask about the shop", "Never mind"]
        )
        #expect(DialogueMenuMovieBridge.selectedIndex(runtime: harness.runtime) == 1)
        #expect(
            DialogueMenuMovieBridge.speakerNameText(runtime: harness.runtime) == "Belethor"
        )
        #expect(harness.log.calls["SetSpeakerName"]?.first == [.string("Belethor")])
    }

    @Test
    func rowsCarryTheFieldNamesTheMovieReads() throws {
        let harness = try makeRuntime()
        DialogueMenuMovieBridge.publish(model(["One"]), runtime: harness.runtime)
        let entries = try #require(
            harness.list.object.lookup(DialogueMenuMovieBridge.entryArrayName)?
                .property.value.objectValue
        )
        let row = try #require(entries.lookup("0")?.property.value.objectValue)
        #expect(row.lookup("text")?.property.value == .string("One"))
        #expect(row.lookup("topicIndex")?.property.value == .integer(0))
        #expect(row.lookup("topicIsNew")?.property.value == .boolean(false))
        // The winning INFO's FormID: the identity OpenSky addresses a response
        // by, in the field the vanilla host names the response in.
        #expect(row.lookup("responseHash")?.property.value == .number(0x100))
    }

    @Test
    func anEmptyListIsClearedRatherThanOnlyInvalidated() throws {
        let harness = try makeRuntime()
        DialogueMenuMovieBridge.publish(model(["One", "Two"]), runtime: harness.runtime)
        #expect(harness.log.count("ClearList") == 0)
        DialogueMenuMovieBridge.publish(model([]), runtime: harness.runtime)
        // `InvalidateData` rebuilds as many clips as there are rows and leaves
        // the rest holding the last publish's text, so an emptied list has to
        // be cleared or it keeps showing the previous conversation.
        #expect(harness.log.count("ClearList") == 1)
        #expect(DialogueMenuMovieBridge.topicLabels(runtime: harness.runtime).isEmpty)
        #expect(DialogueMenuMovieBridge.selectedIndex(runtime: harness.runtime) == nil)
    }

    @Test
    func aListBeingSpokenOverSelectsNothing() throws {
        let harness = try makeRuntime()
        var menu = model(["One", "Two"], selected: 1)
        menu.beginResponse(info: FormID(0x100), runs: ["A line."])
        DialogueMenuMovieBridge.publish(menu, runtime: harness.runtime)
        // The rows stay listed — the vanilla menu keeps them behind the line —
        // but nothing is selectable while a response is being said.
        #expect(DialogueMenuMovieBridge.topicLabels(runtime: harness.runtime).count == 2)
        #expect(DialogueMenuMovieBridge.selectedIndex(runtime: harness.runtime) == nil)
    }

    // MARK: - Subtitle

    @Test
    func showsAndHidesTheSpokenLine() throws {
        let harness = try makeRuntime()
        var menu = model(["One"])
        menu.beginResponse(info: FormID(0x100), runs: ["Some may call this junk."])
        DialogueMenuMovieBridge.publish(menu, runtime: harness.runtime)
        #expect(
            DialogueMenuMovieBridge.subtitleText(runtime: harness.runtime)
                == "Some may call this junk."
        )
        #expect(harness.log.calls["ShowDialogueText"]?.first
            == [.string("Some may call this junk.")])

        menu.showTopicList()
        DialogueMenuMovieBridge.publish(menu, runtime: harness.runtime)
        #expect(DialogueMenuMovieBridge.subtitleText(runtime: harness.runtime)?.isEmpty == true)
        #expect(harness.log.count("HideDialogueText") == 1)
        #expect(harness.log.count("ShowDialogueList") == 1)
    }

    // MARK: - State

    @Test
    func writesTheMoviesOwnStateField() throws {
        let harness = try makeRuntime()
        var menu = model(["One"])
        DialogueMenuMovieBridge.publish(menu, runtime: harness.runtime)
        #expect(DialogueMenuMovieBridge.menuState(runtime: harness.runtime) == 1)
        menu.beginResponse(info: FormID(0x100), runs: ["Said."])
        DialogueMenuMovieBridge.publish(menu, runtime: harness.runtime)
        #expect(DialogueMenuMovieBridge.menuState(runtime: harness.runtime) == 2)
    }

    @Test
    func aMovieWithNoStateVocabularyIsLeftAlone() throws {
        let harness = try makeRuntime(withMenuClass: false)
        DialogueMenuMovieBridge.publish(model(["One"]), runtime: harness.runtime)
        // No class, no constants, no number to write — and no crash, which is
        // the AS2 scope decision's rule for an unmeasured entry point.
        #expect(DialogueMenuMovieBridge.menuState(runtime: harness.runtime) == nil)
        #expect(DialogueMenuMovieBridge.topicLabels(runtime: harness.runtime) == ["One"])
    }

    // MARK: - Degradation

    @Test
    func aMovieWithoutTheMenuReportsEveryEntryPointMissing() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        #expect(
            DialogueMenuMovieBridge.missingEntryPoints(runtime: runtime)
                == DialogueMenuMovieBridge.requiredEntryPoints
        )
        // Publishing into it must be a no-op rather than a trap: the panel
        // reports the missing entry points and the conversation degrades to the
        // engine-side model.
        DialogueMenuMovieBridge.publish(model(["One"]), runtime: runtime)
        #expect(DialogueMenuMovieBridge.topicLabels(runtime: runtime).isEmpty)
    }

    @Test
    func aCompleteMovieReportsNothingMissing() throws {
        let harness = try makeRuntime()
        #expect(DialogueMenuMovieBridge.missingEntryPoints(runtime: harness.runtime).isEmpty)
    }

    // MARK: - Input

    @Test
    func mapsOnlyTheKeysTheMenuHas() {
        #expect(DialogueMenuMovieBridge.key(for: .move(.up))?.code == SWFKeyCode.up)
        #expect(DialogueMenuMovieBridge.key(for: .move(.down))?.code == SWFKeyCode.down)
        #expect(DialogueMenuMovieBridge.key(for: .button(.accept))?.code == SWFKeyCode.enter)
        #expect(DialogueMenuMovieBridge.key(for: .button(.cancel))?.code == SWFKeyCode.escape)
        // One vertical list: left and right mean nothing here, and a pointer
        // delta has no absolute stage position to hit-test with, which is the
        // same call the inventory and system menus made.
        #expect(DialogueMenuMovieBridge.key(for: .move(.left)) == nil)
        #expect(DialogueMenuMovieBridge.key(for: .move(.right)) == nil)
        #expect(DialogueMenuMovieBridge.key(for: .pointer(deltaX: 1, deltaY: 1)) == nil)
    }
}
