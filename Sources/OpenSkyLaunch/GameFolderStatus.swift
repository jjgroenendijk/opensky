// The game folder as the launcher and Settings show it, so the two cannot
// disagree about which install is in use or why none is.

import Foundation
import OpenSkyGameData

nonisolated public struct GameFolderStatus: Equatable, Sendable {
    /// The install folder, or nil when no valid install was found.
    public let path: String?
    /// Where the path came from, or why there is none.
    public let note: String

    public var isFound: Bool {
        path != nil
    }

    public init(path: String?, note: String) {
        self.path = path
        self.note = note
    }

    public init(locate: () throws -> GameDataRoot = { try GameDataLocator.locate() }) {
        do {
            let root = try locate()
            self.init(
                path: root.installURL.path(percentEncoded: false),
                note: Self.sourceNote(for: root.source)
            )
        } catch {
            self.init(path: nil, note: error.localizedDescription)
        }
    }

    public func canStart(_ mode: LaunchMode) -> Bool {
        isFound || !mode.requiresGameData
    }

    public static func sourceNote(for source: GameDataRoot.Source) -> String {
        switch source {
        case .environment:
            "Set by the \(GameDataLocator.environmentKey) environment variable — "
                + "it overrides the choice made here."
        case .userDefaults:
            "Chosen in Settings."
        case .steamDefault:
            "Default Steam install location."
        }
    }
}
