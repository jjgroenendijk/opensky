// The measured AS2 contract of `Interface\tutorialmenu.swf`, the help topic screen.
// The engine writes `/Menu_mc/TitleText` and the `HelpText` text area, then calls
// `ApplyButtonArt`, which asks `GetButtonFromUserEvent` for each `[Event]` tag.
// The exit button calls `CloseMenu`. See docs/engine/messages.md#help-topics.

import Foundation
import OpenSkyFormatsSWF

nonisolated public enum TutorialMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\tutorialmenu.swf"
    public static let menuPath = "/Menu_mc"

    /// `buttonName` answers a controlmap user event, such as "Activate", with its key.
    public static func prepare(
        runtime: SWFMovieRuntime,
        buttonName: @escaping @MainActor @Sendable (String) -> String?,
        onClose: @escaping @MainActor @Sendable () -> Void
    ) {
        for name in ["PlaySound", "myLog"] {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        MenuMovieButtonArt.register(runtime: runtime, buttonName: buttonName)
        runtime.registerHostFunction("CloseMenu") { _ in
            MainActor.assumeIsolated { onClose() }
            return .undefined
        }
    }

    /// The root `InitExtensions` wires the exit button; `SetPlatform` shows the mouse one.
    public static func activate(runtime: SWFMovieRuntime) {
        runtime.callMovie("InitExtensions")
        runtime.callMovie(
            "SetPlatform",
            arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
    }

    public static func publish(title: String, text: String, runtime: SWFMovieRuntime) {
        MenuMovieText.set(title, atPath: "\(menuPath)/TitleText", runtime: runtime)
        MenuMovieText.assign(
            .string(text), member: "text", atPath: "\(menuPath)/HelpText", runtime: runtime
        )
        runtime.callMovie("ApplyButtonArt", atPath: menuPath)
    }
}
