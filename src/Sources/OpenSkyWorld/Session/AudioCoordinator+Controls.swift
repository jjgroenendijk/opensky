// The audio mixer and director controls. Each reads its default
// and does nothing until audio is enabled.

public import OpenSkyAudio

extension AudioCoordinator {
    public var audioMasterVolume: Float {
        get { engine?.masterVolume ?? 1 }
        set { engine?.masterVolume = newValue }
    }

    public func setAudioVolume(_ volume: Float, for category: AudioCategory) {
        engine?.setVolume(volume, for: category)
    }

    var sfxEnabled: Bool {
        get { soundDirector?.sfxEnabled ?? true }
        set { soundDirector?.sfxEnabled = newValue }
    }

    var musicEnabled: Bool {
        get { musicDirector?.musicEnabled ?? true }
        set { musicDirector?.musicEnabled = newValue }
    }

    func forceMusicType(named name: String) -> AudioTriggerRefusal? {
        guard let musicDirector else { return .audioNotEnabled }
        return musicDirector.forcePlayMusicType(named: name).map(AudioTriggerRefusal.music)
    }

    var currentMusicStateName: String {
        musicDirector?.currentStateName ?? "unknown"
    }

    var footstepsEnabled: Bool {
        get { footstepDirector?.footstepsEnabled ?? true }
        set { footstepDirector?.footstepsEnabled = newValue }
    }

    var currentFootstepTags: [String] {
        guard let footstepDirector, let gait = world?.playerGait else { return [] }
        return footstepDirector.tags(for: gait)
    }

    var footstepCounts: (routed: Int, played: Int) {
        guard let footstepDirector else { return (0, 0) }
        return (footstepDirector.routedEventCount, footstepDirector.playedFootstepCount)
    }

    func forcePlayFootstep(tag: String) -> AudioTriggerRefusal? {
        guard let footstepDirector else { return .audioNotEnabled }
        guard let gait = world?.playerGait, let position = world?.playerFeetPosition else {
            return .noRenderer
        }
        return footstepDirector.forcePlayFootstep(tag: tag, gait: gait, position: position)
    }
}
