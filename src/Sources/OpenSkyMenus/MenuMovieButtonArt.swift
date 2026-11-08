// `[Event]` tags in a movie's text become key art: the movie's `CreateButtonArt` or
// `ApplyButtonArt` asks `GetButtonFromUserEvent` for each controlmap user event.

import Foundation
import OpenSkyFormatsSWF

nonisolated enum MenuMovieButtonArt {
    /// `buttonName` answers a user event, such as "Activate", with its key, such as "E".
    static func register(
        runtime: SWFMovieRuntime,
        buttonName: @escaping @MainActor @Sendable (String) -> String?
    ) {
        runtime.registerHostFunction("GetButtonFromUserEvent") { call in
            guard case let .string(event)? = call.arguments.first else { return nil }
            let name = MainActor.assumeIsolated { buttonName(event) }
            return name.map(AS2Value.string)
        }
    }
}
