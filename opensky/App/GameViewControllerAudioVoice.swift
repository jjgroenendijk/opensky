// Renderer/engine bridge for World > Audio > Voice (item 17.5): the picker
// over the install's `.fuz` corpus, the positional trigger, and the playback
// clock readout.
//
// The corpus is 75,408 files, so the picker is a filter rather than a list: the
// provider caches the archive's voice paths once, narrows them by the user's
// substring, and hands the panel the first `VoiceLabState.pickerLimit` matches
// beside the true match count. Truncating silently would read as "that is all
// there is".

import AppKit
import simd

/// Voice picker and playback state. Stored on `GameViewController` because
/// extensions cannot add state.
struct VoiceLabState {
    /// Matches the picker lists at once. A popup is unusable past a few
    /// hundred entries and the filter is the real navigation.
    static let pickerLimit = 200
    /// Where a triggered line lands: straight ahead of the camera, the same
    /// offset the Sources trigger uses, so panning is obvious at once.
    static let offsetUnits: Float = 700

    /// Substring the picker narrows the corpus by. Starts on a voice-type
    /// directory so the picker is useful before the user types anything.
    var filter = "sound\\voice\\skyrim.esm\\femaleeventoned\\"
    /// Every `.fuz` path the archives hold, enumerated once.
    var cachedPaths: [String]?
    /// Matches of the current filter, cached with the filter that produced it.
    var matches: [String] = []
    var matchedFilter: String?
    /// The line last started, and the source it is playing on.
    var playing: VoicePlayback?
    var playingPath: String?
    /// Set by the engine's finished callback when that source played out.
    var finished = false
    var lastError: String?
}

extension GameViewController {
    var voiceFileFilter: String {
        get { voice.filter }
        set {
            guard newValue != voice.filter else { return }
            voice.filter = newValue
        }
    }

    var selectableVoiceFileNames: [String] {
        Array(matchedVoicePaths().prefix(VoiceLabState.pickerLimit))
    }

    var voiceFileMatchCount: Int {
        matchedVoicePaths().count
    }

    func playVoiceFile(named name: String) -> String? {
        guard let worldAudio, worldAudio.isRunning else {
            voice.lastError = "audio engine is not running"
            return voice.lastError
        }
        guard let audioFileSystem else {
            voice.lastError = "no game data"
            return voice.lastError
        }
        let camera = renderer?.freeFlyCamera
        let position = (camera?.position ?? .zero)
            + AudioSpace.worldForward(yaw: camera?.yaw ?? 0, pitch: 0)
            * VoiceLabState.offsetUnits
        do {
            let playback = try worldAudio.playVoice(
                fuzData: audioFileSystem.contents(forPath: name),
                name: name,
                worldPosition: position
            )
            observeVoiceCompletion(engine: worldAudio)
            voice.playing = playback
            voice.playingPath = name
            voice.finished = false
            voice.lastError = nil
            return nil
        } catch {
            voice.lastError = String(describing: error)
            return voice.lastError
        }
    }

    var currentVoiceDescription: String? {
        guard let path = voice.playingPath, let playback = voice.playing else { return nil }
        let lip = playback.lipData.map { "\($0.count) lip bytes" } ?? "no lip data"
        let length = playback.duration.map { String(format: "%.2f s", $0) } ?? "unknown length"
        return "\(Self.shortVoiceName(path)) — \(length), \(lip)"
    }

    var voicePlaybackDescription: String {
        guard let playback = voice.playing else { return "" }
        let total = playback.duration.map { String(format: "%.2f", $0) } ?? "?"
        guard !voice.finished else {
            return "Position: finished at \(total) s"
        }
        guard
            let position = worldAudio?.playbackPosition(ofSource: playback.sourceID)
        else {
            return "Position: no reading (source retired or not yet rendering)"
        }
        return String(format: "Position: %.2f / %@ s", position, total)
    }

    var lastVoiceError: String? {
        voice.lastError
    }

    // MARK: - Internals

    /// Narrows the cached corpus, memoized on the filter that produced it: the
    /// panel reads the list and the count on every 2 Hz refresh, and filtering
    /// 75,408 paths twice a tick is wasted work.
    private func matchedVoicePaths() -> [String] {
        let paths: [String]
        if let cached = voice.cachedPaths {
            paths = cached
        } else {
            paths = (audioFileSystem?.archiveEntries() ?? [])
                .map(\.path)
                .filter { $0.hasSuffix(".fuz") }
                .sorted()
            voice.cachedPaths = paths
        }
        if voice.matchedFilter == voice.filter {
            return voice.matches
        }
        let needle = voice.filter.lowercased().replacingOccurrences(of: "/", with: "\\")
        let matches = needle.isEmpty ? paths : paths.filter { $0.contains(needle) }
        voice.matches = matches
        voice.matchedFilter = voice.filter
        return matches
    }

    /// Subscribes to the engine's line-finished callback once. The engine
    /// reports a source that played to its end, which is what turns the
    /// readout from a running clock into "finished" rather than into "no
    /// reading" once the source is retired.
    private func observeVoiceCompletion(engine: WorldAudioEngine) {
        guard engine.onSourceFinished == nil else { return }
        engine.onSourceFinished = { [weak self] id in
            guard let self, voice.playing?.sourceID == id else { return }
            voice.finished = true
        }
    }

    /// Voice-type directory plus file name, which is the part of a voice path
    /// that identifies the line inside a panel column.
    static func shortVoiceName(_ path: String) -> String {
        path.split(separator: "\\").suffix(2).joined(separator: "\\")
    }
}
