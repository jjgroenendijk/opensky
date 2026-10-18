// A text file a menu shows, such as the credits, read and decoded off the main
// actor (docs/decisions/concurrency.md).

import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData

nonisolated public enum MenuTextFile {
    /// The file's text, or nil when the install lacks it.
    @concurrent
    public static func load(_ path: String, from files: any GameFileSource) async -> String? {
        guard let data = try? files.contents(forPath: path) else { return nil }
        return GameText.decode(data)
    }
}
