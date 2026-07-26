// Renderer/engine bridge for the World > Audio panel (M9.1.3). Same shape as
// the other provider extensions: everything runs on the main actor, and with no
// engine, data or renderer the provider degrades to `AudioStatsSnapshot.empty`
// and an empty picker so the panel never crashes.

import AppKit
import simd

/// Where a panel-triggered source lands: straight ahead of the camera, far
/// enough (~10 m) that turning or strafing produces obvious panning.
private enum AudioTriggerPlacement {
    static let offsetUnits: Float = 700
}

extension GameViewController: AudioControlProviding {
    var audioEnabled: Bool {
        get { worldAudio?.isEnabled ?? false }
        set {
            if newValue, worldAudio == nil {
                let engine = WorldAudioEngine()
                worldAudio = engine
                // The renderer's per-frame tick drives the listener pose.
                renderer?.worldAudio = engine
                buildSoundDirectorIfNeeded(engine: engine)
                buildMusicDirectorIfNeeded(engine: engine)
            }
            worldAudio?.isEnabled = newValue
        }
    }

    /// Pulls the sound/aspc stores off the cell provider and constructs the
    /// world SFX director with the new engine. Idempotent — repeated enables
    /// reuse the existing director. The director subscribes to streamer
    /// callbacks at construction time and remains a no-op until the engine is
    /// also running.
    private func buildSoundDirectorIfNeeded(engine: WorldAudioEngine) {
        guard soundDirector == nil else { return }
        let provider = streamerCellProvider
        let weatherStore = (provider as? WeatherProviding)?.weatherSystem?.store
        let soundStore = (provider as? AudioDataProviding)?.soundStore
        let aspcStore = (provider as? AudioDataProviding)?.aspcStore
        soundDirector = WorldAudioSoundDirector(
            engine: engine,
            soundStore: soundStore,
            weatherStore: weatherStore,
            aspcStore: aspcStore,
            fileSystem: audioFileSystem
        )
    }

    /// Same policy as the SFX director: pulls the music + weather stores off
    /// the cell provider, builds the director once, and hands it to the
    /// renderer so the per-frame audio tick advances the playlist.
    private func buildMusicDirectorIfNeeded(engine: WorldAudioEngine) {
        guard musicDirector == nil else { return }
        let provider = streamerCellProvider
        let director = WorldMusicDirector(
            engine: engine,
            musicStore: (provider as? AudioDataProviding)?.musicStore,
            weatherStore: (provider as? WeatherProviding)?.weatherSystem?.store,
            fileSystem: audioFileSystem
        )
        musicDirector = director
        renderer?.musicDirector = director
    }

    var audioMasterVolume: Float {
        get { worldAudio?.masterVolume ?? 1 }
        set { worldAudio?.masterVolume = newValue }
    }

    func audioVolume(for category: AudioCategory) -> Float {
        worldAudio?.volume(for: category) ?? 1
    }

    func setAudioVolume(_ volume: Float, for category: AudioCategory) {
        worldAudio?.setVolume(volume, for: category)
    }

    func audioCategoryIsMuted(_ category: AudioCategory) -> Bool {
        worldAudio?.isMuted(category) ?? false
    }

    func setAudioCategoryMuted(_ muted: Bool, for category: AudioCategory) {
        worldAudio?.setMuted(muted, for: category)
    }

    var soloedAudioCategory: AudioCategory? {
        get { worldAudio?.soloedCategory }
        set { worldAudio?.soloedCategory = newValue }
    }

    var selectableAudioFileNames: [String] {
        if let cachedAudioFileNames {
            return cachedAudioFileNames
        }
        let names = (audioFileSystem?.archiveEntries() ?? [])
            .map(\.path)
            .filter { $0.lowercased().hasSuffix(".xwm") }
            .sorted()
        cachedAudioFileNames = names
        return names
    }

    func playAudioFile(named name: String) -> String? {
        guard let worldAudio, worldAudio.isRunning else {
            return "audio engine is not running"
        }
        guard let audioFileSystem else {
            return "no game data"
        }
        let camera = renderer?.freeFlyCamera
        let position = (camera?.position ?? .zero)
            + AudioSpace.worldForward(yaw: camera?.yaw ?? 0, pitch: 0)
            * AudioTriggerPlacement.offsetUnits
        do {
            let data = try audioFileSystem.contents(forPath: name)
            // Vanilla `.xwm` is all music, but the trigger exercises the
            // positional-effects path, so it plays under the effects category.
            try worldAudio.playPositional(fileData: data, request: AudioPlayRequest(
                name: name, category: .effects, worldPosition: position
            ))
            return nil
        } catch {
            return String(describing: error)
        }
    }

    func stopAllAudioSources() {
        worldAudio?.stopAllSources()
    }

    var audioStatsSnapshot: AudioStatsSnapshot {
        worldAudio?.statsSnapshot() ?? .empty
    }

    // MARK: - World SFX director bridges (M9.2.2)

    var sfxEnabled: Bool {
        get { soundDirector?.sfxEnabled ?? true }
        set { soundDirector?.sfxEnabled = newValue }
    }

    var ambienceEnabled: Bool {
        get { soundDirector?.ambienceEnabled ?? true }
        set { soundDirector?.ambienceEnabled = newValue }
    }

    func stopAmbience() {
        // Force an empty context through the director: it retires the current
        // bed and caches the empty one, so ambience stays off until the next
        // cell change emits a fresh (non-empty) context.
        soundDirector?.handleAmbienceContext(.empty)
    }

    var lastSFXDescription: String? {
        soundDirector?.lastSFXDescription
    }

    var lastSFXError: String? {
        soundDirector?.lastSFXError
    }

    var currentAmbienceDescription: String {
        soundDirector?.currentAmbienceDescription ?? "none"
    }

    // MARK: - Music director bridges (M9.2.3)

    var musicEnabled: Bool {
        get { musicDirector?.musicEnabled ?? true }
        set { musicDirector?.musicEnabled = newValue }
    }

    var selectableMusicTypeNames: [String] {
        musicDirector?.selectableMusicTypeNames ?? []
    }

    func forceMusicType(named name: String) -> String? {
        guard let musicDirector else { return "audio is not enabled" }
        return musicDirector.forcePlayMusicType(named: name)
    }

    func stopMusic() {
        musicDirector?.stopMusic()
    }

    var currentMusicDescription: String {
        musicDirector?.currentMusicDescription ?? "none"
    }

    var currentMusicStateName: String {
        musicDirector?.currentStateName ?? "unknown"
    }

    var currentMusicTrackName: String? {
        musicDirector?.currentTrackName
    }

    var lastMusicError: String? {
        musicDirector?.lastMusicError
    }
}
