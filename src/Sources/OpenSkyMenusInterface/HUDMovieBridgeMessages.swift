import Foundation
import OpenSkyFormatsSWF

/// One centred HUD notice. The movie writes both lines in capitals.
nonisolated public struct HUDBigNotice: Equatable, Sendable {
    nonisolated public enum Kind: Equatable, Sendable {
        case quest
        case shout
    }

    public let kind: Kind
    public let title: String
    public let status: String
    /// The `SNDR` editor ID the notice plays, such as `UIQuestNew`.
    public let sound: String?

    public init(kind: Kind = .quest, title: String, status: String, sound: String? = nil) {
        self.kind = kind
        self.title = title
        self.status = status
        self.sound = sound
    }
}
