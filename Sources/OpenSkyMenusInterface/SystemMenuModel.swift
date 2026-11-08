import Foundation

/// The page the menu shows. A sub-page has its own model in the coordinator.
nonisolated public enum SystemMenuPage: String, Equatable, Sendable {
    case main, settings, controls, save, load, quit, installedContent, help

    /// The Help and Installed Content pages: a topic list and the text of one topic.
    public var isTopicPage: Bool {
        self == .installedContent || self == .help
    }
}
