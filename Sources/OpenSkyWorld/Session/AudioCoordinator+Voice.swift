// World > Audio > Voice: the picker over the 75,408 `.fuz` lines, the
// positional trigger, the playback clock, and lip sync on the speaker.

import OpenSkyAudio
import OpenSkyFormatsAnimation
import OpenSkyGameData
import OSLog

struct VoiceLabState {
    var filter = AudioLabCore.defaultVoiceFilter
    var cachedPaths: [String]?
    var matches: [String] = []
    /// The filter `matches` was computed for.
    var matchedFilter: String?
    var playing: VoicePlayback?
    var playingPath: String?
    var finished = false
    var lastError: String?
    var lipSyncEnabled = true
    var lipPlayback: LipSyncPlayback?
    var lipError: String?
}

extension AudioCoordinator {
    private static let lipSyncLogger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "LipSync"
    )

    public var voiceFileFilter: String {
        get { voice.filter }
        set { voice.filter = newValue }
    }

    public var selectableVoiceFileNames: [String] {
        Array(matchedVoicePaths().prefix(AudioLabCore.voicePickerLimit))
    }

    public var voiceFileMatchCount: Int {
        matchedVoicePaths().count
    }

    public func playVoiceFile(named name: String) -> String? {
        guard let engine, engine.isRunning else {
            voice.lastError = "audio engine is not running"
            return voice.lastError
        }
        guard let fileSystem = world?.audioFileSystem else {
            voice.lastError = "no game data"
            return voice.lastError
        }
        do {
            let playback = try engine.playVoice(
                fuzData: fileSystem.contents(forPath: name),
                name: name,
                worldPosition: triggerPosition()
            )
            observeVoiceCompletion(engine: engine)
            voice.playing = playback
            voice.playingPath = name
            voice.finished = false
            voice.lastError = nil
            startLipSync(playback: playback, path: name)
            return nil
        } catch {
            voice.lastError = String(describing: error)
            return voice.lastError
        }
    }

    public var currentVoiceDescription: String? {
        guard let path = voice.playingPath, let playback = voice.playing else { return nil }
        return AudioLabCore.voiceDescription(path: path, playback: playback)
    }

    public var voicePlaybackDescription: String {
        guard let playback = voice.playing else { return "" }
        return AudioLabCore.playbackDescription(
            playback: playback,
            finished: voice.finished,
            position: engine?.playbackPosition(ofSource: playback.sourceID)
        )
    }

    public var lastVoiceError: String? {
        voice.lastError
    }

    public var lipSyncEnabled: Bool {
        get { voice.lipSyncEnabled }
        set {
            voice.lipSyncEnabled = newValue
            voice.lipPlayback?.isEnabled = newValue
        }
    }

    public var lipSyncSnapshot: LipSyncSnapshot {
        voice.lipPlayback?.snapshot ?? .empty
    }

    public var lastLipSyncError: String? {
        voice.lipError
    }

    /// The panel reads the list and the count on every 2 Hz refresh, so the
    /// matches are kept until the filter changes.
    private func matchedVoicePaths() -> [String] {
        let paths: [String]
        if let cached = voice.cachedPaths {
            paths = cached
        } else {
            paths = AudioLabCore.voicePaths(in: world?.audioFileSystem?.archiveEntries() ?? [])
            voice.cachedPaths = paths
        }
        if voice.matchedFilter == voice.filter {
            return voice.matches
        }
        voice.matches = AudioLabCore.voiceMatches(in: paths, filter: voice.filter)
        voice.matchedFilter = voice.filter
        return voice.matches
    }

    /// Without this, a retired source reads "no reading" instead of "finished".
    private func observeVoiceCompletion(engine: WorldAudioEngine) {
        guard engine.onSourceFinished == nil else { return }
        engine.onSourceFinished = { [weak self] id in
            guard let self, voice.playing?.sourceID == id else { return }
            voice.finished = true
            voice.lipPlayback?.finish(at: world?.audioAnimationTime ?? 0)
        }
    }

    private func startLipSync(playback: VoicePlayback, path: String) {
        voice.lipPlayback?.resetToBindPose()
        voice.lipPlayback = nil
        guard voice.lipSyncEnabled else {
            voice.lipError = nil
            return
        }
        guard let lipData = playback.lipData else {
            voice.lipError = "line has no lip data"
            Self.lipSyncLogger.info("[INFO] lip sync miss: line has no lip data")
            return
        }
        guard let lipPlayback = world?.lipSyncTarget() else {
            voice.lipError = "no selected actor with expression TRI bindings"
            Self.lipSyncLogger.info("[INFO] lip sync miss: no selected actor")
            return
        }
        do {
            let track = try LIPFile(data: lipData)
            lipPlayback.isEnabled = true
            lipPlayback.start(
                track: track,
                clock: playback.clock,
                line: AudioLabCore.shortVoiceName(path),
                animationTime: world?.audioAnimationTime ?? 0
            )
            voice.lipPlayback = lipPlayback
            voice.lipError = nil
        } catch {
            voice.lipError = String(describing: error)
            Self.lipSyncLogger.error(
                "[ERROR] lip decode: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
