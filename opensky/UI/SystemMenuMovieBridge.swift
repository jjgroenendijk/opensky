// Vanilla presentation layer for the system menu (M8.5.1): the measured AS2
// contract of `Interface\startmenu.swf`. Device-free and AppKit-free so it
// builds into the CLI target and can be unit-tested against synthetic AS2
// fixtures; it owns no renderer and no movie lifetime. The engine-side selector
// it presents is UI/SystemMenuModel.swift.
//
// The 8.3.3 measurement rejected this movie on three grounds. Two are gone:
// the 35 `callDepthExceeded` faults were retired by the `super` resolution fix
// (issue #136), and `_root.CodeObj` turned out not to be a host object at all —
// the movie's own `StartMenu` constructor creates it (`_root.CodeObj =
// this.codeObj = new Object()`) and only ever calls out through it, all 16
// names on the Bethesda.net login path. The third, the save-list data contract,
// still stands and is why this bridge reports no saves.
//
// Scope note recorded from the same measurement: `startmenu.swf` is Skyrim's
// title screen, so its rows are Continue/New/Load/Quit and its 1,674-string
// pool contains no `$SETTINGS`. The engine-side selector, not this movie, is
// what carries Resume/Settings/Quit. See docs/engine/system-menu.md.

import Foundation

nonisolated enum SystemMenuMovieBridge {
    static let moviePath = "interface\\startmenu.swf"
    /// The `StartMenu` instance. `SetPlatform` and `InitExtensions` are direct
    /// methods on it, not `GameDelegate` callbacks.
    static let menuPath = "/MenuHolder/Menu_mc"

    /// `PLATFORM_PC_KBMOUSE`, the value the movie's platform switch expects for
    /// keyboard and mouse.
    static let pcPlatform = 0.0

    /// Trace sink. The movie routes `myLog` out through `GameDelegate.call`,
    /// 24 times inside its own `DoInitAction` blocks; every one was an
    /// unhandled call before this. Answering it keeps the invoke log's
    /// unhandled count meaningful instead of drowned in known-benign trace.
    /// `StartState` and `currentState` are the movie's own state
    /// notifications, emitted on every transition; `PlaySound`/`PlayOKSound`
    /// are the UI sound bank OpenSky does not have yet.
    static let sinkHostFunctions = [
        "myLog", "PlaySound", "PlayOKSound", "StartState", "currentState"
    ]

    /// Scaleform's UI-sound hook, which the movie reaches for as a plain
    /// `_global` function rather than through `GameDelegate`. OpenSky has no UI
    /// sound bank yet, so it is a no-op rather than a missing name.
    static let globalSinkFunctions = ["gfxProcessSound"]

    /// Every name the bytecode calls on `_root.CodeObj`, all of them on the
    /// Bethesda.net login path (`StartMenu` and `BethesdaNetLogin`). OpenSky
    /// implements none of them; attaching no-ops keeps a menu that never opens
    /// the login screen from accumulating unresolved calls.
    static let codeObjectMethods = [
        "initLogin", "BeginLogin", "GetBnetUpdate", "ModsBlockedByBnet",
        "CClubBlockedByPermissions", "CClubBlockedByBnet",
        "startEditText", "endEditText", "onLoginScreenOpen", "onLoginScreenClose",
        "attemptLogin", "createQuickAccount", "AcceptLegalDoc", "PopulateEULA",
        "PlaySound", "PlayOKSound"
    ]

    /// The rows the movie can activate. Only `QuitToDesktop` has an engine
    /// meaning today; the rest are logged so the invoke log shows the movie
    /// reaching a real engine seam rather than a missing name.
    static let actionHostFunctions = [
        "CONTINUE", "NEW", "LOAD", "MOD", "HELP", "CREDITS",
        "QuitToDesktop", "QuitToMainMenu", "OnDisabledLoadPress",
        "fadeOutStarted", "EndPressStartState"
    ]

    /// The row whose activation means "terminate", so the host can honour the
    /// vanilla menu's own Quit rather than only the engine selector's.
    static let quitHostFunction = "QuitToDesktop"

    // MARK: - Bring-up

    /// Installs the surface the movie reaches for *during* `start()`. Bring-up
    /// is the first thing that calls out to the host, so this must run before
    /// the runtime is started (`Renderer.startSWFRuntime(prepare:)`).
    static func prepare(runtime: SWFMovieRuntime) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        let global = runtime.runtime.globalObject
        for name in globalSinkFunctions {
            AS2Natives.method(runtime.runtime, on: global, name: name) { _ in .undefined }
        }
    }

    /// Drives the started movie into its populated `Main` state. Runs after
    /// `start()` because `_root.CodeObj` does not exist until the `StartMenu`
    /// constructor has run. `onQuit` fires when the movie's own Quit row is
    /// activated.
    ///
    /// Nothing here throws. A movie that does not match the measured contract
    /// leaves entries in the missing-API tally, which the panel reports.
    static func activate(
        runtime: SWFMovieRuntime,
        version: String,
        onQuit: @escaping @Sendable () -> Void
    ) {
        attachCodeObjectMethods(runtime: runtime)
        registerActions(runtime: runtime, onQuit: onQuit)
        runtime.callMovie("SetPlatform", atPath: menuPath, arguments: [
            .number(pcPlatform), .boolean(false)
        ])
        runtime.callMovie("InitExtensions", atPath: menuPath)
        runtime.callMovie("sendMenuProperties", arguments: menuProperties(version: version))
    }

    /// The 14 flat arguments `StartMenu.setupMainMenu` reads. OpenSky has no
    /// save system, no downloadable content, and no Bethesda.net account, so
    /// every capability flag is false and the list comes up as New, Load
    /// (disabled), Credits, Quit.
    static func menuProperties(version: String) -> [AS2Value] {
        [
            .boolean(true), // 0  show Quit
            .boolean(false), // 1  has saves -> no Continue, Load disabled
            .string(version), // 2  version string
            .boolean(false), // 3  false leaves the Press Start state
            .boolean(false), // 4  Sky10 upsell banner
            .boolean(false), // 5  downloadable content
            .boolean(false), // 6  help
            .boolean(false), // 7  mod manager
            .boolean(false), // 8  creations
            .boolean(true), // 9  logged in -> no login screen
            .boolean(false), // 10 read, branch is a no-op
            .boolean(false), // 11 PS5 transfer data
            .boolean(false), // 12 creations icon
            .boolean(false) // 13 creation club access
        ]
    }

    // MARK: - Readout

    /// Faults and distinct unresolved names, for the verification readout.
    static func diagnostics(runtime: SWFMovieRuntime) -> (faults: Int, missingNames: Int) {
        let tally = runtime.tally
        return (tally.faultTotal, tally.missingNames.count)
    }

    /// The movie's own state name (`PressStart`, `Main`, `SaveLoad`, …), which
    /// is how the panel shows that `sendMenuProperties` actually landed.
    static func currentState(runtime: SWFMovieRuntime) -> String? {
        guard
            let menu = runtime.node(atPath: menuPath, from: runtime.root),
            case let .string(state) = menu.object.lookup(stateName)?.property.value
        else {
            return nil
        }
        return state
    }

    /// The row labels the movie actually built, read back from the list's own
    /// entry array. Empty until `activate` has run, which is exactly the
    /// distinction the panel readout needs to show.
    static func entryLabels(runtime: SWFMovieRuntime) -> [String] {
        guard
            let menu = runtime.node(atPath: menuPath, from: runtime.root),
            let list = menu.object.lookup("MainList")?.property.value.objectValue,
            let entries = list.lookup(entryArrayName)?.property.value.objectValue
        else {
            return []
        }
        // `entryList` is an AS2 array, so its rows are numeric property names.
        // Sort numerically — lexical order would put row 10 before row 2.
        let indexed: [(Int, String)] = entries.ownPropertyNames.compactMap { name in
            guard let index = Int(name) else { return nil }
            return (index, name)
        }
        return indexed
            .sorted { $0.0 < $1.0 }
            .compactMap { _, name in
                guard
                    let row = entries.lookup(name)?.property.value.objectValue,
                    case let .string(text) = row.lookup("text")?.property.value
                else {
                    return nil
                }
                return text
            }
    }

    // MARK: - Private

    private static func attachCodeObjectMethods(runtime: SWFMovieRuntime) {
        guard
            let codeObject = runtime.root.object
                .lookup(codeObjectName)?.property.value.objectValue
        else {
            runtime.runtime.noteMissing(codeObjectName)
            return
        }
        for name in codeObjectMethods {
            AS2Natives.method(runtime.runtime, on: codeObject, name: name) { _ in .undefined }
        }
    }

    private static func registerActions(
        runtime: SWFMovieRuntime,
        onQuit: @escaping @Sendable () -> Void
    ) {
        for name in actionHostFunctions {
            if name == quitHostFunction {
                runtime.registerHostFunction(name) { _ in
                    onQuit()
                    return .undefined
                }
            } else {
                runtime.registerHostFunction(name) { _ in .undefined }
            }
        }
    }

    static let codeObjectName = "CodeObj"

    /// `Shared.BSScrollingList`'s backing array of row objects. The list's
    /// `Entry0`…`Entry16` members are the reusable row clips; this is the data.
    static let entryArrayName = "EntriesA"

    /// `StartMenu`'s own state field.
    static let stateName = "strCurrentState"
}
