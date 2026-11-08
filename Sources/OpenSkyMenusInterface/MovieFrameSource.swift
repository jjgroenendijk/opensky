import Foundation
import OpenSkyAudio
import OpenSkyFormatsAudio
import OpenSkyFormatsCore
import OpenSkyGameData
import Synchronization

/// The arguments of `Game.PlayBink` (<https://ck.uesp.net/wiki/PlayBink_-_Game>).
nonisolated public struct MovieRequest: Equatable, Sendable {
    /// A file under `Data\Video`, such as `BGS_Logo.bik`.
    public var fileName: String
    public var interruptible: Bool
    public var muteAudio: Bool
    public var muteMusic: Bool
    public var letterbox: Bool

    public init(
        fileName: String, interruptible: Bool = false, muteAudio: Bool = true,
        muteMusic: Bool = true, letterbox: Bool = true
    ) {
        self.fileName = fileName
        self.interruptible = interruptible
        self.muteAudio = muteAudio
        self.muteMusic = muteMusic
        self.letterbox = letterbox
    }

    /// The path in the game's file system.
    public var path: String {
        let name = fileName.replacingOccurrences(of: "/", with: "\\")
        return name.lowercased().hasPrefix("video\\") ? name : "video\\" + name
    }
}
