// Why the music director did not start the music it was asked for.

import OpenSkyFormatsESM

nonisolated public enum MusicRefusal: Equatable, Sendable {
    case noMusicData
    case unknownMusicType(String)
    case noPlayableTrack(FormID)
    case noCombatMusicType
    case noPlayableCombatTrack
    /// The default objects name no music for this tag, such as `LUMS`.
    case noSpecialMusic(String)
    /// `path` is the track's authored path; `reason` the thrown error's description.
    case trackFailed(path: String, reason: String)

    public var text: String {
        switch self {
        case .noMusicData: "no music data"
        case let .unknownMusicType(name): "unknown music type \(name)"
        case let .noPlayableTrack(formID): "no playable track for \(formID.description)"
        case .noCombatMusicType: "no combat music type in the load order"
        case .noPlayableCombatTrack: "no playable combat track"
        case let .noSpecialMusic(tag): "no \(tag) music in the default objects"
        case let .trackFailed(path, reason): "\(path): \(reason)"
        }
    }
}
