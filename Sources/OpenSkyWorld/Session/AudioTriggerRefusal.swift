// Why an audio trigger did not start its sound. A trigger returns nil
// when the sound started or waits for its file.

import OpenSkyFormatsESM

nonisolated public enum AudioTriggerRefusal: Equatable, Sendable {
    case engineNotRunning
    case audioNotEnabled
    case noGameData
    case noRenderer
    case noFootstepRecords
    case noSoundRecords
    case tagUnresolved(tag: String, footstepSet: String)
    case soundUnresolved(tag: String, sound: FormID)
    case music(MusicRefusal)
    /// `reason` is the thrown error's or the failed load's description.
    case playFailed(reason: String)

    public var text: String {
        switch self {
        case .engineNotRunning: "audio engine is not running"
        case .audioNotEnabled: "audio is not enabled"
        case .noGameData: "no game data"
        case .noRenderer: "no renderer"
        case .noFootstepRecords: "no footstep records"
        case .noSoundRecords: "no sound records"
        case let .tagUnresolved(tag, footstepSet): "\(tag) resolves to no sound in \(footstepSet)"
        case let .soundUnresolved(tag, sound): "unresolved \(tag) -> \(sound.description)"
        case let .music(refusal): refusal.text
        case let .playFailed(reason): reason
        }
    }
}
