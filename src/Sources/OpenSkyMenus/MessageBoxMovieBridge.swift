// The measured AS2 contract of `Interface\messagebox.swf`. The movie registers
// `setMessageText`, `setButtons`, `setIsVertical`, and `setIsCancellable`, and
// calls `buttonPress([index])` when a button is clicked or the box is cancelled.
// See docs/engine/messages.md#message-boxes.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyMenusInterface

nonisolated enum MessageBoxMovieBridge: Sendable {
    static let moviePath = "interface\\messagebox.swf"
    static let menuPath = "/MessageMenu"
    static let sinkHostFunctions = ["PlaySound", "myLog"]

    /// `buttonPress` carries the button's position among the buttons sent.
    static func prepare(
        runtime: SWFMovieRuntime,
        onButton: @escaping @MainActor @Sendable (Int) -> Void
    ) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        runtime.registerHostFunction("buttonPress") { call in
            guard case let .number(index)? = call.arguments.first, index.isFinite else {
                return .undefined
            }
            MainActor.assumeIsolated { onButton(Int(index)) }
            return .undefined
        }
    }

    static func activate(runtime: SWFMovieRuntime) {
        runtime.callMovie(
            "SetPlatform",
            atPath: menuPath,
            arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
    }

    /// Sends one box. A one-button box can be cancelled, as the engine model allows.
    static func publish(_ request: MessageBoxRequest, runtime: SWFMovieRuntime) {
        let text = [request.title, request.text]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: "\n\n")
        runtime.callMovie("setMessageText", arguments: [.string(text), .boolean(false)])
        runtime.callMovie("setIsVertical", arguments: [.boolean(request.buttons.count > 2)])
        runtime.callMovie(
            "setIsCancellable",
            arguments: [.boolean(request.buttons.count == 1), .integer(0)]
        )
        runtime.callMovie(
            "setButtons",
            arguments: [.boolean(true)] + request.buttons.map { .string($0.text) }
        )
    }

    /// Moves the movie's focus to the button at `row`, which draws its highlight.
    static func highlight(row: Int, runtime: SWFMovieRuntime) {
        guard
            let menu = runtime.node(atPath: menuPath, from: runtime.root),
            let buttons = menu.object.lookup("MessageButtons")?.property.value.objectValue,
            buttons.elements.indices.contains(row)
        else { return }
        runtime.focus(SWFDisplayObject.resolve(buttons.elements[row].objectValue))
    }
}
