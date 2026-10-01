// The mixer and director controls of World > Audio. Each reads its default
// and does nothing until audio is enabled.

import OpenSkyAudio
import OpenSkyFormatsESM

extension AudioCoordinator: AudioControlProviding {
    public var audioMasterVolume: Float {
        get { engine?.masterVolume ?? 1 }
        set { engine?.masterVolume = newValue }
    }

    public func audioVolume(for category: AudioCategory) -> Float {
        engine?.volume(for: category) ?? 1
    }

    public func setAudioVolume(_ volume: Float, for category: AudioCategory) {
        engine?.setVolume(volume, for: category)
    }

    public func audioCategoryIsMuted(_ category: AudioCategory) -> Bool {
        engine?.isMuted(category) ?? false
    }

    public func setAudioCategoryMuted(_ muted: Bool, for category: AudioCategory) {
        engine?.setMuted(muted, for: category)
    }

    public var soloedAudioCategory: AudioCategory? {
        get { engine?.soloedCategory }
        set { engine?.soloedCategory = newValue }
    }

    public func stopAllAudioSources() {
        engine?.stopAllSources()
    }

    public var audioStatsSnapshot: AudioStatsSnapshot {
        engine?.statsSnapshot() ?? .empty
    }

    public var sfxEnabled: Bool {
        get { soundDirector?.sfxEnabled ?? true }
        set { soundDirector?.sfxEnabled = newValue }
    }

    public var ambienceEnabled: Bool {
        get { soundDirector?.ambienceEnabled ?? true }
        set { soundDirector?.ambienceEnabled = newValue }
    }

    /// The empty context stays cached, so ambience stays off until the next cell change.
    public func stopAmbience() {
        soundDirector?.handleAmbienceContext(.empty)
    }

    public var lastSFXDescription: String? {
        soundDirector?.lastSFXDescription
    }

    public var lastSFXError: String? {
        soundDirector?.lastSFXError
    }

    public var currentAmbienceDescription: String {
        soundDirector?.currentAmbienceDescription ?? "none"
    }

    public var musicEnabled: Bool {
        get { musicDirector?.musicEnabled ?? true }
        set { musicDirector?.musicEnabled = newValue }
    }

    public var selectableMusicTypeNames: [String] {
        musicDirector?.selectableMusicTypeNames ?? []
    }

    public func forceMusicType(named name: String) -> String? {
        guard let musicDirector else { return "audio is not enabled" }
        return musicDirector.forcePlayMusicType(named: name)
    }

    public func stopMusic() {
        musicDirector?.stopMusic()
    }

    public var currentMusicDescription: String {
        musicDirector?.currentMusicDescription ?? "none"
    }

    public var currentMusicStateName: String {
        musicDirector?.currentStateName ?? "unknown"
    }

    public var lastMusicError: String? {
        musicDirector?.lastMusicError
    }

    public var footstepsEnabled: Bool {
        get { footstepDirector?.footstepsEnabled ?? true }
        set { footstepDirector?.footstepsEnabled = newValue }
    }

    public var currentFootstepSetDescription: String {
        footstepDirector?.footstepSetDescription ?? "none"
    }

    public var currentFootstepTags: [String] {
        guard let footstepDirector, let gait = world?.playerGait else { return [] }
        return footstepDirector.tags(for: gait)
    }

    public var lastFootstepDescription: String? {
        footstepDirector?.lastFootstepDescription
    }

    public var lastFootstepError: String? {
        footstepDirector?.lastFootstepError
    }

    public var footstepCounts: (routed: Int, played: Int) {
        guard let footstepDirector else { return (0, 0) }
        return (footstepDirector.routedEventCount, footstepDirector.playedFootstepCount)
    }

    public var currentFootstepMaterialDescription: String {
        footstepDirector?.materialDescription ?? "none"
    }

    public var footstepMaterialOptions: [(id: FormID, name: String)] {
        footstepDirector?.selectableMaterials ?? []
    }

    /// Nil follows the ground contact.
    public var forcedFootstepMaterial: FormID? {
        get { footstepDirector?.forcedMaterial }
        set { footstepDirector?.forcedMaterial = newValue }
    }

    public func forcePlayFootstep(tag: String) -> String? {
        guard let footstepDirector else { return "audio is not enabled" }
        guard let gait = world?.playerGait, let position = world?.playerFeetPosition else {
            return "no renderer"
        }
        return footstepDirector.forcePlayFootstep(tag: tag, gait: gait, position: position)
    }
}
