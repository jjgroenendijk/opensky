// Voice playback and the playback clock (item 17.5). Satellite of
// WorldAudioEngine.swift, which owns the graph, and of
// WorldAudioEngineSources.swift, which owns source lifecycle.
//
// A voice line is a `.fuz` container: a lip-sync blob followed by a complete
// RIFF/XWMA stream. The container is framed here and its payload handed to
// `XWMFile`, so the line streams down exactly the positional route a `.xwm`
// sound effect takes — same streamer, same decoder, same environment node —
// with nothing in `AudioSourceStreamer` needing to learn a second container.
// The lip blob is returned to the caller untouched for item 17.7.
//
// Documented in docs/engine/audio.md.

import AVFAudio
import Foundation
import simd

/// What a started voice line hands back: the source to track, how long the
/// line runs, and the lip-sync bytes that came with it.
nonisolated struct VoicePlayback: Equatable {
    /// Source id, for `playbackPosition(ofSource:)`, `stopSource(id:)` and the
    /// `onSourceFinished` callback.
    let sourceID: Int
    /// Playing time in seconds from the xWMA packet table, or nil when the
    /// stream carries no `dpds` chunk.
    let duration: Double?
    /// `.lip` bytes from the container, or nil when the line ships without
    /// them. Not decoded here — item 17.7 owns that.
    let lipData: Data?
}

extension WorldAudioEngine {
    /// Plays one `.fuz` voice line at the speaker's head, on the voice submix.
    ///
    /// - Parameters:
    ///   - fuzData: the whole `.fuz` file as the VFS returned it.
    ///   - name: the VFS path, which is what the source readout shows.
    ///   - worldPosition: the speaker's head in native Skyrim units.
    ///   - gain: per-source gain on top of the voice category volume.
    @discardableResult
    func playVoice(
        fuzData: Data,
        name: String,
        worldPosition: SIMD3<Float>,
        gain: Float = 1
    ) throws -> VoicePlayback {
        let container = try FUZFile(data: fuzData)
        let audio = try container.audio()
        let sourceID = try playPositional(
            file: audio,
            request: AudioPlayRequest(
                name: name,
                category: .voice,
                worldPosition: worldPosition,
                gain: gain
            )
        )
        return VoicePlayback(
            sourceID: sourceID,
            duration: audio.declaredDuration,
            lipData: container.lipData
        )
    }

    /// How far into its material a source has played, in seconds, or nil when
    /// no source has that id or nothing has been rendered since it started.
    ///
    /// This is elapsed-render accounting against `playbackClockSeconds`, not a
    /// query of the player node. `AVAudioPlayerNode.playerTime(forNodeTime:)`
    /// would be the obvious reading and was written first; it hangs the test
    /// host under offline manual rendering, deterministically, on the toolchain
    /// this repo builds with (dated note in docs/tools/environment.md). The
    /// accounting below cannot block, because it is subtraction: the engine
    /// clock reads `manualRenderingSampleTime` offline and accumulates the
    /// renderer's paused-aware frame delta live, and each source remembers the
    /// clock it started at.
    ///
    /// What that costs is honesty about *scheduling* versus *sound*: the value
    /// is time elapsed since the source was started, so a streamed source whose
    /// first chunk is still decoding reads a few milliseconds ahead of what has
    /// actually reached the output. Subtitles and lip sync want elapsed line
    /// time, which is exactly this; sample-accurate output position is not
    /// available without the node query.
    func playbackPosition(ofSource id: Int) -> Double? {
        guard let source = sources.first(where: { $0.id == id }) else { return nil }
        let elapsed = playbackClockSeconds - source.startClockSeconds
        return elapsed > 0 ? elapsed : nil
    }

    /// The engine's monotonic playback clock in seconds.
    ///
    /// Offline it is the manual-rendering sample time, so it advances by
    /// exactly the frames each `renderOffline(_:to:)` call produced and by
    /// nothing else — which is what makes the clock tests deterministic. Live
    /// it is the accumulated frame delta the renderer's audio tick feeds in,
    /// which is paused-aware, so the clock freezes in menu mode along with the
    /// fades rather than jumping on resume.
    var playbackClockSeconds: Double {
        guard engine.manualRenderingMode == .offline else { return liveClockSeconds }
        let sampleRate = engine.manualRenderingFormat.sampleRate
        guard sampleRate > 0 else { return liveClockSeconds }
        return Double(engine.manualRenderingSampleTime) / sampleRate
    }
}
