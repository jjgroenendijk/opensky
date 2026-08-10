// Vanilla presentation layer for the dialogue menu (issue #205, roadmap item
// 17.3): the measured AS2 contract of `Interface\dialoguemenu.swf`.
//
// Device-free and AppKit-free so it builds into the CLI target and can be unit
// tested against synthetic AS2 fixtures; it owns no renderer and no movie
// lifetime. The engine-side model it publishes is UI/DialogueMenuModel.swift.
//
// `docs/decisions/swf-as2-scope.md` deferred this movie's host APIs to the
// milestone that owns its data and set the rule every unimplemented one follows
// here: a logged no-op plus a tally entry, never a crash.
//
// ## What was measured, and how
//
// `openskycli swf action-run --movie dialoguemenu.swf` brings the movie up
// through the same `SWFMovieRuntime` the app uses. It starts and ticks with
// **zero faults and zero unimplemented opcodes**, 57 display nodes, and 18
// distinct unresolved names, none of which is an engine entry point. Nothing
// below is taken from memory of the shipped game.
//
// Display shape (`--tree-depth 5`):
//
//   /DialogueMenu_mc                        the menu, class `DialogueMenuObj`
//   /DialogueMenu_mc/SpeakerName            who is talking
//   /DialogueMenu_mc/SubtitleText           the line being said
//   /DialogueMenu_mc/ExitButton             frame labels up/over/down/disabled
//   /DialogueMenu_mc/TopicListHolder        frame labels moveDown, moveUp,
//                                           topicClicked, fadeListIn,
//                                           slideListIn
//   /DialogueMenu_mc/TopicListHolder/List_mc  class `TopicList`; the topic rows
//
// The registered classes are `DialogueMenuObj`, `TopicList` and `Button`
// (`--dump-class`). `DialogueMenuObj` publishes its own state vocabulary as
// class constants — `SHOW_GREETING` 0, `TOPIC_LIST_SHOWN` 1, `TOPIC_CLICKED` 2,
// `TRANSITIONING` 3 — and the live instance carries `eMenuState`, so the menu's
// state is read off the movie rather than tracked twice.
//
// The list is the same CLIK family every other OpenSky menu drives
// (`--dump-proto`): `TopicList` adds `UpdateList`, `SetSelectedTopic`,
// `SetEntryText` and `RepositionEntries` over a `BSScrollingList` base that
// carries `EntriesA`, `iSelectedIndex` with -1 for none, `InvalidateData` and
// `ClearList`. `iMaxItemsShown` is 8 and `iNumTopHalfEntries` is 4, which is
// why the movie ships eight `Entry` clips and centres the selection.
//
// The row field names are measured rather than guessed: `swf action-sweep
// --movie dialoguemenu.swf` structurally resolves `text`, `topicIndex`,
// `topicIsNew` and `responseHash` off the rows the movie is handed.
// `swf dialogue-menu --probe-rows` is the cross-check the journal used, and on
// this list it reports something worth writing down: publishing rows with no
// fields at all moves no row-field name into the missing tally at all. The
// centred list draws a row through the entry clip's own `SetEntryText` rather
// than by reading named properties off the row on the way past, so the
// structural sweep is the measurement here and the probe only confirms that
// nothing else is read.
//
// Documented in docs/engine/dialogue-menu.md.

import Foundation

/// The three tallies a dialogue bring-up is gated on. Zero of each is the gate
/// passing; the panel and the CLI probe print all three even at zero, so a
/// passing gate cannot be mistaken for a missing readout.
nonisolated struct DialogueMenuDiagnostics: Equatable, Sendable {
    let faults: Int
    let missingNames: Int
    let unhandledInvokes: Int

    static let none = DialogueMenuDiagnostics(
        faults: 0, missingNames: 0, unhandledInvokes: 0
    )
}

nonisolated enum DialogueMenuMovieBridge {
    static let moviePath = "interface\\dialoguemenu.swf"
    /// The placed `DialogueMenuObj` instance, which is where every engine
    /// entry point lives.
    static let menuPath = "/DialogueMenu_mc"
    static let speakerNamePath = "\(menuPath)/SpeakerName"
    static let subtitleTextPath = "\(menuPath)/SubtitleText"
    static let topicListHolderPath = "\(menuPath)/TopicListHolder"
    static let topicListPath = "\(topicListHolderPath)/List_mc"
    static let exitButtonPath = "\(menuPath)/ExitButton"

    /// The list base's backing array and selection, shared with every other
    /// CLIK list in the game.
    static let entryArrayName = "EntriesA"
    static let selectedIndexName = "iSelectedIndex"
    static let invalidateMethod = "InvalidateData"
    static let clearMethod = "ClearList"
    /// `TopicList`'s own rebuild, which repositions the centred entries after
    /// `InvalidateData` has rebuilt them.
    static let updateListMethod = "UpdateList"
    /// `TopicList`'s own selection setter, which moves the highlight and the
    /// centring together.
    static let selectTopicMethod = "SetSelectedTopic"

    /// The instance property holding the menu's own state, whose values are the
    /// four `DialogueMenuObj` class constants.
    static let menuStateName = "eMenuState"
    static let stateConstantNames = [
        "SHOW_GREETING", "TOPIC_LIST_SHOWN", "TOPIC_CLICKED", "TRANSITIONING"
    ]
    /// The class the constants and the prototype methods are read off.
    static let menuClassName = "DialogueMenuObj"
    static let listClassName = "TopicList"

    /// Engine entry points on the menu instance that OpenSky drives.
    static let requiredEntryPoints = [
        "PopulateDialogueLists",
        "SetSpeakerName",
        "ShowDialogueText",
        "HideDialogueText",
        "ShowDialogueList"
    ]

    /// Entry points the movie publishes that OpenSky does not drive yet, with
    /// the milestone each belongs to. Listed rather than silently absent
    /// because `docs/decisions/swf-as2-scope.md` requires an unimplemented host
    /// API to be an accounted no-op: a reader of this file should be able to
    /// tell "not reached yet" from "does not exist".
    ///
    /// * `OnVoiceReady` and `SkipText` are the voice clock's, item 17.5. Line
    ///   timing is what tells the menu a line finished, and OpenSky has none
    ///   until `.fuz` playback lands, so responses advance on input instead.
    /// * `SetAllowProgress` and `StartProgressTimer` gate the same thing from
    ///   the movie's side, on the 750 ms `ALLOW_PROGRESS_DELAY` its class
    ///   carries.
    /// * `AdjustForPALSD` is a standard-definition television layout the macOS
    ///   target has no use for.
    static let deferredEntryPoints = [
        "OnVoiceReady", "SkipText", "SetAllowProgress", "StartProgressTimer",
        "AdjustForPALSD"
    ]

    /// `PLATFORM_PC_KBMOUSE`, the same value the system menu's platform switch
    /// takes.
    static let pcPlatform = SystemMenuMovieBridge.pcPlatform

    /// Movie-to-engine calls with no OpenSky consumer on this surface. Sunk
    /// rather than left missing so a bring-up's unhandled-invoke count means
    /// "something the engine should answer and does not".
    static let sinkHostFunctions = ["myLog", "PlaySound", "PlayOKSound"]

    // MARK: - Bring-up

    /// Installs the surface the movie reaches for *during* `start()`. Bring-up
    /// is the first thing that calls out to the host, so this must run before
    /// the runtime is started (`Renderer.startSWFRuntime(prepare:)`).
    static func prepare(runtime: SWFMovieRuntime) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        let global = runtime.runtime.globalObject
        for name in SystemMenuMovieBridge.globalSinkFunctions {
            AS2Natives.method(runtime.runtime, on: global, name: name) { _ in .undefined }
        }
    }

    /// Whether the movie exposes every entry point this bridge drives.
    ///
    /// Reported rather than thrown, unlike `HUDMovieBridge.validate`: the
    /// dialogue menu degrades to an engine-side list when the movie's shape has
    /// moved, and taking the app down at the moment a conversation starts is
    /// the one outcome the AS2 scope decision rules out.
    static func missingEntryPoints(runtime: SWFMovieRuntime) -> [String] {
        guard let menu = runtime.node(atPath: menuPath, from: runtime.root) else {
            return requiredEntryPoints
        }
        return requiredEntryPoints.filter {
            menu.object.lookup($0)?.property.value.functionValue == nil
        }
    }

    /// Opens the menu, registering the close callback the exit button and the
    /// goodbye path both reach.
    ///
    /// Nothing here throws. A movie that does not match the measured contract
    /// leaves entries in the missing-API tally, which the panel reports.
    static func activate(
        runtime: SWFMovieRuntime,
        onClose: @escaping @MainActor @Sendable () -> Void
    ) {
        runtime.registerHostFunction("CloseMenu") { _ in
            MainActor.assumeIsolated { onClose() }
            return .undefined
        }
        runtime.callMovie("SetPlatform", atPath: menuPath, arguments: [.number(pcPlatform)])
        runtime.callMovie("InitExtensions", atPath: menuPath)
    }

    // MARK: - Input

    /// Routes the toolkit-free engine menu event into the Flash key model.
    ///
    /// Pointer events are not routed, matching the inventory and system menus:
    /// a `MenuInputEvent.pointer` carries a delta and the movie's hit test
    /// needs an absolute stage position, so there is nothing honest to hand it.
    /// Scope point 5 of issue #205 made that conditional on the inventory
    /// precedent, and the precedent skips it.
    ///
    /// - Returns: whether the movie consumed the event.
    @discardableResult
    static func handle(_ event: MenuInputEvent, runtime: SWFMovieRuntime) -> Bool {
        guard let key = key(for: event) else { return false }
        let down = runtime.handle(.keyDown(code: key.code, ascii: key.ascii))
        let up = runtime.handle(.keyUp(code: key.code))
        return down || up
    }

    static func key(for event: MenuInputEvent) -> (code: Int, ascii: Int)? {
        switch event {
        case .move(.up): (SWFKeyCode.up, 0)
        case .move(.down): (SWFKeyCode.down, 0)
        case .move(.left), .move(.right): nil
        case .button(.accept): (SWFKeyCode.enter, 13)
        case .button(.cancel): (SWFKeyCode.escape, 0)
        case .pointer: nil
        }
    }

    // MARK: - Readout

    /// The three tallies the bring-up gate reads.
    static func diagnostics(runtime: SWFMovieRuntime) -> DialogueMenuDiagnostics {
        let tally = runtime.tally
        return DialogueMenuDiagnostics(
            faults: tally.faultTotal,
            missingNames: tally.missingNames.count,
            unhandledInvokes: runtime.invokeLog.unhandled
        )
    }

    /// The value one of the movie's own state constants carries, so the state
    /// this bridge publishes can be asserted against the movie instead of
    /// pinned to a number here.
    static func stateConstant(_ name: String, runtime: SWFMovieRuntime) -> Int? {
        guard
            let menuClass = runtime.runtime.registeredClass(named: menuClassName),
            case let .number(value) = menuClass.lookup(name)?.property.value,
            value.isFinite
        else {
            return nil
        }
        return Int(value)
    }

    /// The state the live movie is in, read off its own `eMenuState`.
    static func menuState(runtime: SWFMovieRuntime) -> Int? {
        guard
            let menu = runtime.node(atPath: menuPath, from: runtime.root),
            case let .number(value) = menu.object.lookup(menuStateName)?.property.value,
            value.isFinite
        else {
            return nil
        }
        return Int(value)
    }
}
