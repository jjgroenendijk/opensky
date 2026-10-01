// Lets the app's provider object stand in for its `AudioCoordinator`, so the
// panel registry keeps one provider value without a forward per member.

import OpenSkyAudio
import OpenSkyFormatsESM

public protocol AudioControlForwarding: AudioControlProviding {
    var audio: AudioCoordinator { get }
}

extension AudioControlForwarding {
    public var audioEnabled: Bool {
        get { audio.audioEnabled }
        set { audio.audioEnabled = newValue }
    }

    public var audioMasterVolume: Float {
        get { audio.audioMasterVolume }
        set { audio.audioMasterVolume = newValue }
    }

    public func audioVolume(for category: AudioCategory) -> Float {
        audio.audioVolume(for: category)
    }

    public func setAudioVolume(_ volume: Float, for category: AudioCategory) {
        audio.setAudioVolume(volume, for: category)
    }

    public func audioCategoryIsMuted(_ category: AudioCategory) -> Bool {
        audio.audioCategoryIsMuted(category)
    }

    public func setAudioCategoryMuted(_ muted: Bool, for category: AudioCategory) {
        audio.setAudioCategoryMuted(muted, for: category)
    }

    public var soloedAudioCategory: AudioCategory? {
        get { audio.soloedAudioCategory }
        set { audio.soloedAudioCategory = newValue }
    }

    public var selectableAudioFileNames: [String] {
        audio.selectableAudioFileNames
    }

    public func playAudioFile(named name: String) -> String? {
        audio.playAudioFile(named: name)
    }

    public func stopAllAudioSources() {
        audio.stopAllAudioSources()
    }

    public var audioStatsSnapshot: AudioStatsSnapshot {
        audio.audioStatsSnapshot
    }

    public var voiceFileFilter: String {
        get { audio.voiceFileFilter }
        set { audio.voiceFileFilter = newValue }
    }

    public var selectableVoiceFileNames: [String] {
        audio.selectableVoiceFileNames
    }

    public var voiceFileMatchCount: Int {
        audio.voiceFileMatchCount
    }

    public func playVoiceFile(named name: String) -> String? {
        audio.playVoiceFile(named: name)
    }

    public var currentVoiceDescription: String? {
        audio.currentVoiceDescription
    }

    public var voicePlaybackDescription: String {
        audio.voicePlaybackDescription
    }

    public var lastVoiceError: String? {
        audio.lastVoiceError
    }

    public var lipSyncEnabled: Bool {
        get { audio.lipSyncEnabled }
        set { audio.lipSyncEnabled = newValue }
    }

    public var lipSyncSnapshot: LipSyncSnapshot {
        audio.lipSyncSnapshot
    }

    public var lastLipSyncError: String? {
        audio.lastLipSyncError
    }

    public var sfxEnabled: Bool {
        get { audio.sfxEnabled }
        set { audio.sfxEnabled = newValue }
    }

    public var ambienceEnabled: Bool {
        get { audio.ambienceEnabled }
        set { audio.ambienceEnabled = newValue }
    }

    public func stopAmbience() {
        audio.stopAmbience()
    }

    public var lastSFXDescription: String? {
        audio.lastSFXDescription
    }

    public var lastSFXError: String? {
        audio.lastSFXError
    }

    public var currentAmbienceDescription: String {
        audio.currentAmbienceDescription
    }

    public var musicEnabled: Bool {
        get { audio.musicEnabled }
        set { audio.musicEnabled = newValue }
    }

    public var selectableMusicTypeNames: [String] {
        audio.selectableMusicTypeNames
    }

    public func forceMusicType(named name: String) -> String? {
        audio.forceMusicType(named: name)
    }

    public func stopMusic() {
        audio.stopMusic()
    }

    public var currentMusicDescription: String {
        audio.currentMusicDescription
    }

    public var currentMusicStateName: String {
        audio.currentMusicStateName
    }

    public var lastMusicError: String? {
        audio.lastMusicError
    }

    public var footstepsEnabled: Bool {
        get { audio.footstepsEnabled }
        set { audio.footstepsEnabled = newValue }
    }

    public var currentFootstepSetDescription: String {
        audio.currentFootstepSetDescription
    }

    public var currentFootstepTags: [String] {
        audio.currentFootstepTags
    }

    public var lastFootstepDescription: String? {
        audio.lastFootstepDescription
    }

    public var lastFootstepError: String? {
        audio.lastFootstepError
    }

    public var footstepCounts: (routed: Int, played: Int) {
        audio.footstepCounts
    }

    public var currentFootstepMaterialDescription: String {
        audio.currentFootstepMaterialDescription
    }

    public var footstepMaterialOptions: [(id: FormID, name: String)] {
        audio.footstepMaterialOptions
    }

    public var forcedFootstepMaterial: FormID? {
        get { audio.forcedFootstepMaterial }
        set { audio.forcedFootstepMaterial = newValue }
    }

    public func forcePlayFootstep(tag: String) -> String? {
        audio.forcePlayFootstep(tag: tag)
    }
}
