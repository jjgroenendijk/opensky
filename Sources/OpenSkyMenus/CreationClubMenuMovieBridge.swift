// The measured AS2 contract of `Interface\creationclubmenu.swf`. The movie calls the
// engine through a `codeObj` object on `/CreationClub_mc`, not through GameDelegate.
// OpenSky stays offline: every store call does nothing, and closing works.
// See docs/engine/creation-club.md.

import Foundation
import OpenSkyFormatsSWF

/// A call the Creation Club movie makes that the engine acts on.
nonisolated public enum CreationClubMovieEvent: Equatable, Sendable {
    case close
}

nonisolated public enum CreationClubMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\creationclubmenu.swf"
    public static let menuPath = "/CreationClub_mc"
    public static let language = "en"
    /// Store, login, and download calls. Offline, they do nothing.
    static let storeCalls = [
        "AcceptLegalDoc", "DownloadAll", "DownloadCreation", "EnterCreditsScreen",
        "EnterDetailsScreen", "InitCreationClubMenu", "LoadThumbnail", "PopulateEULA",
        "PurchaseMod", "UnregisterImage", "attemptLogin", "createQuickAccount",
        "endEditText", "onDisplayImage", "onLoginScreenClose", "onLoginScreenOpen",
        "startEditText"
    ]
    static let closeCalls = ["confirmCloseManager", "attemptCloseManager"]
    static let soundCalls = ["PlaySound", "PlayOKSound"]

    /// Fills `codeObj`, then tells the movie it is ready, which starts its `Init`.
    public static func activate(
        runtime: SWFMovieRuntime,
        onEvent: @escaping @MainActor @Sendable (CreationClubMovieEvent) -> Void
    ) {
        guard
            let menu = runtime.node(atPath: menuPath, from: runtime.root),
            let codeObject = menu.object.lookup("codeObj")?.property.value.objectValue
        else { return }
        fill(codeObject, runtime: runtime.runtime, onEvent: onEvent)
        runtime.callMovie("onCodeObjectInit", atPath: menuPath, arguments: [.string(language)])
    }

    static func fill(
        _ codeObject: AS2Object, runtime: AS2Runtime,
        onEvent: @escaping @MainActor @Sendable (CreationClubMovieEvent) -> Void
    ) {
        for name in storeCalls + soundCalls {
            AS2Natives.method(runtime, on: codeObject, name: name) { _ in .undefined }
        }
        for name in closeCalls {
            AS2Natives.method(runtime, on: codeObject, name: name) { _ in
                MainActor.assumeIsolated { onEvent(.close) }
                return .undefined
            }
        }
    }

    /// The movie drops its login screen and `codeObj` before it goes.
    public static func release(runtime: SWFMovieRuntime) {
        runtime.callMovie("ReleaseCodeObject", atPath: menuPath)
    }
}
