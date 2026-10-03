// Runs the vanilla `Interface\dialoguemenu.swf` through the AS2 names we measured.
// It has no AppKit, so the CLI builds it and tests use synthetic AS2.
// An unimplemented host call is a logged no-op plus a tally entry.
// The measured contract is in docs/engine/dialogue-menu.md.

import Foundation
import OpenSkyFormatsSWF

/// The three tallies a dialogue bring-up is gated on. Zero of each is the gate
/// passing; the panel and the CLI probe print all three even at zero, so a
/// passing gate cannot be mistaken for a missing readout.
nonisolated public struct DialogueMenuDiagnostics: Equatable, Sendable {
    public let faults: Int
    public let missingNames: Int
    public let unhandledInvokes: Int

    public static let none = DialogueMenuDiagnostics(
        faults: 0, missingNames: 0, unhandledInvokes: 0
    )
}

nonisolated public enum DialogueMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\dialoguemenu.swf"
    /// The placed `DialogueMenuObj` instance, which is where every engine
    /// entry point lives.
    public static let menuPath = "/DialogueMenu_mc"
    public static let speakerNamePath = "\(menuPath)/SpeakerName"
    public static let subtitleTextPath = "\(menuPath)/SubtitleText"
    public static let topicListHolderPath = "\(menuPath)/TopicListHolder"
    public static let topicListPath = "\(topicListHolderPath)/List_mc"

    /// The list base's backing array and selection, shared with every other
    /// CLIK list in the game.
    public static let entryArrayName = MenuMovieEntryList.arrayName
    public static let selectedIndexName = "iSelectedIndex"
    public static let invalidateMethod = "InvalidateData"
    public static let clearMethod = "ClearList"
    /// `TopicList`'s own rebuild, which repositions the centred entries after
    /// `InvalidateData` has rebuilt them.
    public static let updateListMethod = "UpdateList"

    /// The instance property holding the menu's own state, whose values are the
    /// four `DialogueMenuObj` class constants.
    public static let menuStateName = "eMenuState"
    public static let stateConstantNames = [
        "SHOW_GREETING", "TOPIC_LIST_SHOWN", "TOPIC_CLICKED", "TRANSITIONING"
    ]
    /// The class the constants and the prototype methods are read off.
    public static let menuClassName = "DialogueMenuObj"

    /// Engine entry points on the menu instance that OpenSky drives.
    public static let requiredEntryPoints = [
        "PopulateDialogueLists",
        "SetSpeakerName",
        "ShowDialogueText",
        "HideDialogueText",
        "ShowDialogueList"
    ]

    /// Entry points the movie publishes that OpenSky does not drive, listed so
    /// an unimplemented host API is an accounted no-op
    /// (`docs/decisions/swf-as2-scope.md`). `OnVoiceReady`, `SkipText`,
    /// `SetAllowProgress` and `StartProgressTimer` belong to line timing;
    /// responses advance on input instead. `AdjustForPALSD` is a TV layout.
    public static let deferredEntryPoints = [
        "OnVoiceReady", "SkipText", "SetAllowProgress", "StartProgressTimer",
        "AdjustForPALSD"
    ]

    /// `PLATFORM_PC_KBMOUSE`, the same value the system menu's platform switch
    /// takes.
    public static let pcPlatform = SystemMenuMovieBridge.pcPlatform

    /// Movie-to-engine calls with no OpenSky consumer on this surface. Sunk
    /// rather than left missing so a bring-up's unhandled-invoke count means
    /// "something the engine should answer and does not".
    public static let sinkHostFunctions = ["myLog", "PlaySound", "PlayOKSound"]

    // MARK: - Bring-up

    /// Installs the surface the movie reaches for *during* `start()`. Bring-up
    /// is the first thing that calls out to the host, so this must run before
    /// the runtime is started (`Renderer.startSWFRuntime(prepare:)`).
    public static func prepare(runtime: SWFMovieRuntime) {
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
    public static func missingEntryPoints(runtime: SWFMovieRuntime) -> [String] {
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
    public static func activate(
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

    public static func key(for event: MenuInputEvent) -> (code: Int, ascii: Int)? {
        switch event {
        case .move(.up): (SWFKeyCode.up, 0)
        case .move(.down): (SWFKeyCode.down, 0)
        case .move(.left), .move(.right): nil
        case .button(.accept): (SWFKeyCode.enter, 13)
        case .button(.cancel): (SWFKeyCode.escape, 0)
        case .pointer, .release: nil
        }
    }

    // MARK: - Readout

    /// The three tallies the bring-up gate reads.
    public static func diagnostics(runtime: SWFMovieRuntime) -> DialogueMenuDiagnostics {
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
    public static func stateConstant(_ name: String, runtime: SWFMovieRuntime) -> Int? {
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
    public static func menuState(runtime: SWFMovieRuntime) -> Int? {
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
