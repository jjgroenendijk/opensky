// The measured AS2 contract of `Interface\sleepwaitmenu.swf`. The movie owns the
// hours slider and its keys; it calls `OK([hours])` or `Cancel`. The engine sets the
// date line and the question through `/SleepWaitMenu_mc`. See docs/engine/sleep-wait.md.

import Foundation
import OpenSkyFormatsSWF

/// A call the sleep and wait movie makes.
nonisolated public enum SleepWaitMovieEvent: Equatable, Sendable {
    case wait(hours: Int)
    case cancel
}

nonisolated public enum SleepWaitMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\sleepwaitmenu.swf"
    public static let menuPath = "/SleepWaitMenu_mc"
    public static let sinkHostFunctions = ["PlaySound", "myLog"]

    public static func prepare(
        runtime: SWFMovieRuntime,
        onEvent: @escaping @MainActor @Sendable (SleepWaitMovieEvent) -> Void
    ) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        runtime.registerHostFunction("OK") { call in
            guard case let .number(hours)? = call.arguments.first, hours.isFinite else {
                return .undefined
            }
            MainActor.assumeIsolated { onEvent(.wait(hours: Int(hours))) }
            return .undefined
        }
        runtime.registerHostFunction("Cancel") { _ in
            MainActor.assumeIsolated { onEvent(.cancel) }
            return .undefined
        }
    }

    /// The root `InitExtensions` wires the slider and buttons; `SetPlatform` lays them out.
    public static func activate(runtime: SWFMovieRuntime, sleeping: Bool, date: String) {
        runtime.callMovie("InitExtensions")
        runtime.callMovie(
            "SetPlatform",
            arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
        publish(sleeping: sleeping, date: date, runtime: runtime)
    }

    /// `SetSleeping(true)` asks "Rest how long?"; false asks "Wait how long?".
    public static func publish(sleeping: Bool, date: String, runtime: SWFMovieRuntime) {
        runtime.callMovie("SetSleeping", atPath: menuPath, arguments: [.boolean(sleeping)])
        runtime.callMovie("SetCurrentTime", atPath: menuPath, arguments: [.string(date)])
    }
}
