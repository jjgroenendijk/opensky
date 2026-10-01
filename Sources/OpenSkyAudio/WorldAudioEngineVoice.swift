// Voice playback and the playback clock. A `.fuz` is a lip-sync blob plus a RIFF/XWMA
// stream; the payload goes to `XWMFile` and streams like any `.xwm` effect, so
// `AudioSourceStreamer` knows one container. The lip blob is returned to the caller.
// See docs/engine/audio-decoding.md.

import AVFAudio
import Foundation
import OpenSkyFormatsAudio
import simd

/// What a started voice line hands back: the source to track, how long the
/// line runs, and the lip-sync bytes that came with it.
nonisolated public struct VoicePlayback: Equatable, Sendable {
    /// Source id, for `playbackPosition(ofSource:)`, `stopSource(id:)` and the
    /// `onSourceFinished` callback.
    public let sourceID: Int
    /// Playing time in seconds from the xWMA packet table, or nil when the
    /// stream carries no `dpds` chunk.
    public let duration: Double?
    /// `.lip` bytes from the container, or nil when the line has none. Decoded by lip sync,
    /// not here.
    public let lipData: Data?
    /// Nonisolated snapshot of this source's authoritative playback position.
    /// Starts at zero, advances on the audio tick, and becomes nil when the
    /// source is retired or stopped.
    public let clock: VoicePlaybackClock
}

extension WorldAudioEngine {
    /// Plays one `.fuz` voice line at the speaker's head (native units) on the voice
    /// submix. `name` is the VFS path the readout shows.
    @discardableResult
    public func playVoice(
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
        let clock = VoicePlaybackClock()
        sources.first { $0.id == sourceID }?.voiceClock = clock
        return VoicePlayback(
            sourceID: sourceID,
            duration: audio.declaredDuration,
            lipData: container.lipData,
            clock: clock
        )
    }

    /// Seconds a source has played, or nil. Subtracts its start from
    /// `playbackClockSeconds`, because `playerTime(forNodeTime:)` hangs offline
    /// rendering (docs/tools/environment.md). It may run a few ms ahead of the output.
    public func playbackPosition(ofSource id: Int) -> Double? {
        guard let source = sources.first(where: { $0.id == id }) else { return nil }
        let elapsed = playbackClockSeconds - source.startClockSeconds
        return elapsed > 0 ? elapsed : nil
    }

    /// The monotonic playback clock in seconds. Offline it is the manual-rendering
    /// sample time, so tests are deterministic. Live it sums the renderer's
    /// paused-aware frame delta, so it freezes in menu mode.
    public var playbackClockSeconds: Double {
        guard engine.manualRenderingMode == .offline else { return liveClockSeconds }
        let sampleRate = engine.manualRenderingFormat.sampleRate
        guard sampleRate > 0 else { return liveClockSeconds }
        return Double(engine.manualRenderingSampleTime) / sampleRate
    }
}
