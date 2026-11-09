public import OpenSkyAudio
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface

/// What the world adapters use of `AudioCoordinator`.
public protocol AudioPort: AnyObject {
    associatedtype WorldAudioSoundDirector: WorldAudioSoundDirectorPort
    associatedtype WorldMusicDirector: WorldMusicDirectorPort
    var assets: AudioAssetLoader? { get }
    var audioEnabled: Bool { get set }
    var audioMasterVolume: Float { get set }
    var engine: WorldAudioEngine? { get }
    var musicDirector: WorldMusicDirector? { get }
    var outputMuted: Bool { get set }
    func setAudioVolume(_ volume: Float, for category: AudioCategory)
    var soundDirector: WorldAudioSoundDirector? { get }
    func speak(_ paths: [String], speaker: ReferenceKey, finished: (() -> Void)?)
    func stopSpeaking(_ speaker: ReferenceKey)
    func updateFootstepSet(feetArmatures: [FormID])
}

/// The default arguments a protocol requirement cannot carry.
extension AudioPort {
    public func speak(_ paths: [String], speaker: ReferenceKey) {
        speak(paths, speaker: speaker, finished: nil)
    }
}
