// The measured AS2 contract of `Interface\startmenu.swf`, the main menu. It has
// no renderer, so tests drive it with synthetic AS2. The flags and calls are in
// docs/engine/main-menu.md.

import Foundation
import OpenSkyFormatsSWF

nonisolated public enum TitleMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\startmenu.swf"
    public static let menuPath = "/MenuHolder/Menu_mc"
    public static let listPath = "\(menuPath)/MainListHolder/List_mc"
    /// One panel lists the characters, then one character's saves.
    public static let saveLoadPanelPath = "\(menuPath)/SaveLoadPanel_mc"
    public static let saveLoadListPath = "\(saveLoadPanelPath)/List_mc"
    static let saveLoadStates: Set = ["CharacterSelection", "SaveLoad"]
    public static let mainState = "Main"
    /// Ticks the list needs to lay out its rows after `sendMenuProperties`.
    public static let activationTicks = 20

    /// Movie-to-engine calls that only report sounds, logs, and state names.
    public static let sinkHostFunctions = [
        "myLog", "PlaySound", "StartState", "currentState", "fadeOutStarted"
    ]
    public static let globalSinkFunctions = ["gfxProcessSound"]

    /// The movie's calls when the player picks a main row.
    public enum Request: String, CaseIterable, Sendable {
        case resume = "CONTINUE"
        case new = "NEW"
        case credits = "OpenCreditsMenu"
        case quit = "QuitToDesktop"
    }

    /// The 14 flags of `sendMenuProperties`. Flag 9 set skips the login screen.
    public static func menuProperties(hasSaves: Bool, version: String) -> [AS2Value] {
        var flags = [AS2Value](repeating: .boolean(false), count: 14)
        flags[0] = .boolean(true)
        flags[1] = .boolean(hasSaves)
        flags[2] = .string(version)
        flags[9] = .boolean(true)
        return flags
    }

    /// Runs before `start()`, because bring-up already calls the host.
    public static func prepare(
        runtime: SWFMovieRuntime,
        onRequest: @escaping @MainActor @Sendable (Request) -> Void
    ) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        let global = runtime.runtime.globalObject
        for name in globalSinkFunctions {
            AS2Natives.method(runtime.runtime, on: global, name: name) { _ in .undefined }
        }
        for request in Request.allCases {
            runtime.registerHostFunction(request.rawValue) { _ in
                MainActor.assumeIsolated {
                    onRequest(request)
                }
                return .undefined
            }
        }
    }

    /// Opens the movie on its Main state with the list focused.
    public static func activate(runtime: SWFMovieRuntime, hasSaves: Bool, version: String) {
        runtime.callMovie("SetPlatform", arguments: [.number(0), .boolean(false)])
        runtime.callMovie("InitExtensions")
        runtime.callMovie(
            "sendMenuProperties",
            arguments: menuProperties(hasSaves: hasSaves, version: version)
        )
        runtime.focusTarget = runtime.node(atPath: listPath, from: runtime.root)
    }

    /// The game moves key focus when the movie changes state; OpenSky owns the
    /// focus target, so it follows the state here.
    public static func followStateFocus(runtime: SWFMovieRuntime) {
        let path: String
        switch currentState(runtime: runtime) {
        case mainState: path = listPath
        case let state? where saveLoadStates.contains(state): path = saveLoadListPath
        default: return
        }
        guard
            let node = runtime.node(atPath: path, from: runtime.root),
            runtime.focusTarget !== node
        else { return }
        runtime.focusTarget = node
    }

    /// Leaves a row OpenSky does not draw yet, such as the credits.
    public static func returnToMain(runtime: SWFMovieRuntime) {
        runtime.callMovie("StartState", atPath: menuPath, arguments: [.string(mainState)])
        runtime.focusTarget = runtime.node(atPath: listPath, from: runtime.root)
    }

    @discardableResult
    public static func handle(_ event: MenuInputEvent, runtime: SWFMovieRuntime) -> Bool {
        guard let key = event.swfKey else { return false }
        let down = runtime.handle(.keyDown(code: key.code, ascii: key.ascii))
        let up = runtime.handle(.keyUp(code: key.code))
        return down || up
    }

    public static func entryLabels(runtime: SWFMovieRuntime) -> [String] {
        MenuMovieEntryList.labels(atPath: listPath, runtime: runtime)
    }

    public static func currentState(runtime: SWFMovieRuntime) -> String? {
        guard
            let menu = runtime.node(atPath: menuPath, from: runtime.root),
            case let .string(state) = menu.object.lookup("strCurrentState")?.property.value
        else { return nil }
        return state
    }
}
