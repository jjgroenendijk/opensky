// Where the system menu readout says the game data lives. Finding the data root walks
// the file system, so it runs once.

import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData

final class SystemMenuDataRoot {
    var locate: () -> GameDataRoot? = { attempt { try GameDataLocator.locate() } }
    private var root: GameDataRoot?
    private var resolved = false

    /// The install path and where it came from; both nil without a data root.
    var readout: (path: String?, source: String?) {
        if !resolved {
            root = locate()
            resolved = true
        }
        return (root?.installURL.path(percentEncoded: false), root?.sourceLabel)
    }
}

extension GameDataRoot {
    /// Where the readout says the data root came from.
    var sourceLabel: String {
        switch source {
        case .commandLine: "command line"
        case .environment: "\(GameDataLocator.environmentKey) environment variable"
        case .userDefaults: "Settings"
        case .steamDefault: "Steam default"
        case .steamLibrary: "Steam library"
        }
    }
}
