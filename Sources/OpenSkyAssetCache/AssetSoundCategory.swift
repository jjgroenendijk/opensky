// The sound groups the audio measurements compare, from a sound's folder.

import Foundation

/// Which sound group a cached sound belongs to, from its folder. Dialogue ships
/// as `.fuz` and is not cached, so `voice` holds the creature vocal sounds.
nonisolated public enum AssetSoundCategory: String, CaseIterable, Sendable {
    case effects
    case voice
    case ambience
    case music

    public init(path: String) {
        let folders = path.lowercased().split(whereSeparator: { $0 == "\\" || $0 == "/" })
        if folders.first == "music" {
            self = .music
        } else if folders.contains("voice") || folders.dropFirst(2).first == "voc" {
            self = .voice
        } else if folders.dropFirst(2).first?.hasPrefix("amb") == true {
            self = .ambience
        } else {
            self = .effects
        }
    }
}
