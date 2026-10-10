// Dialogue speech: an actor says the voice files of one line in order, at its
// head, with its mouth driven by the line's lip track. Scenes and the dialogue
// menu speak through it; the World > Audio voice lab stays separate.
// See docs/engine/audio-decoding.md.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyGameData

/// One actor's spoken line: the voice files still to say, in order.
nonisolated struct SpeechQueue: Equatable {
    private(set) var pending: [String]
    private(set) var current: String?
    let count: Int

    init(paths: [String]) {
        pending = paths
        count = paths.count
    }

    /// The next file to say, which becomes `current`.
    mutating func next() -> String? {
        current = pending.isEmpty ? nil : pending.removeFirst()
        return current
    }

    /// One-based position of `current` in the line.
    var position: Int {
        count - pending.count
    }
}

struct SpeechChannel {
    var queue: SpeechQueue
    /// Set while the current file's bytes load.
    var isWaiting = false
    var playing: VoicePlayback?
    var lip: LipSyncPlayback?
    /// Runs when the last file played to its end, not when the line is stopped.
    var finished: (() -> Void)?
}

struct SpeechState {
    var channels: [ReferenceKey: SpeechChannel] = [:]
    var lastError: String?
}

extension AudioCoordinator {
    /// Says `paths` in order as `speaker`, stopping what it was saying. A file
    /// that does not load is skipped, and the reason goes to `lastSpeechError`.
    public func speak(
        _ paths: [String], speaker: ReferenceKey, finished: (() -> Void)? = nil
    ) {
        stopSpeaking(speaker)
        guard !paths.isEmpty else { return }
        guard let engine, engine.isRunning, voiceFiles != nil else {
            speech.lastError = engine?.isRunning == true ? "no game data" : "audio is off"
            return
        }
        observeVoiceCompletion(engine: engine)
        speech.channels[speaker] = SpeechChannel(
            queue: SpeechQueue(paths: paths), finished: finished
        )
        advanceSpeech(speaker)
    }

    /// Cuts `speaker` off. Its finished callback does not run.
    public func stopSpeaking(_ speaker: ReferenceKey) {
        guard let channel = speech.channels.removeValue(forKey: speaker) else { return }
        if let playing = channel.playing {
            engine?.stopSource(id: playing.sourceID)
        }
        channel.lip?.resetToBindPose()
    }

    /// Whether `speaker` is saying or loading a line.
    public func isSpeaking(_ speaker: ReferenceKey) -> Bool {
        speech.channels[speaker] != nil
    }

    /// One row per speaking actor, for the Voice section.
    public var speechDescription: String {
        let rows = speech.channels.keys.sorted().compactMap { speaker -> String? in
            guard let channel = speech.channels[speaker], let path = channel.queue.current else {
                return nil
            }
            let state = channel.isWaiting ? "loading" : "playing"
            return "\(speaker) · \(AudioLabCore.shortVoiceName(path)) · "
                + "\(channel.queue.position) of \(channel.queue.count) · \(state)"
        }
        var lines = rows.isEmpty
            ? ["Dialogue speech: nobody speaking"]
            : ["Dialogue speech:"] + rows
        if let error = speech.lastError {
            lines.append("Speech failed: \(error)")
        }
        return lines.joined(separator: "\n")
    }

    public var lastSpeechError: String? {
        speech.lastError
    }

    /// Starts the files that waited for their bytes. Called from `drainVoice`.
    func drainSpeech() {
        for (speaker, channel) in speech.channels where channel.isWaiting {
            playCurrent(speaker)
        }
    }

    func speechSourceFinished(_ id: Int) {
        guard
            let speaker = speech.channels.first(where: { $0.value.playing?.sourceID == id })?.key
        else { return }
        speech.channels[speaker]?.lip?.finish(at: world?.audioAnimationTime ?? 0)
        speech.channels[speaker]?.playing = nil
        advanceSpeech(speaker)
    }

    /// Moves to the next file, or ends the line when none is left.
    private func advanceSpeech(_ speaker: ReferenceKey) {
        guard speech.channels[speaker]?.queue.next() != nil else {
            let finished = speech.channels.removeValue(forKey: speaker)?.finished
            finished?()
            return
        }
        playCurrent(speaker)
    }

    private func playCurrent(_ speaker: ReferenceKey) {
        guard
            let channel = speech.channels[speaker],
            let path = channel.queue.current,
            let voiceFiles, let engine
        else { return }
        speech.channels[speaker]?.isWaiting = false
        switch voiceFiles.state(of: path) {
        case .loading:
            speech.channels[speaker]?.isWaiting = true
        case let .failed(failure):
            speech.lastError = "\(AudioLabCore.shortVoiceName(path)): \(failure.reason)"
            skip(speaker)
        case let .ready(data):
            voiceFiles.evict { $0 == path }
            do {
                let playback = try engine.playVoice(
                    fuzData: data,
                    name: path,
                    worldPosition: world?.speakerHeadPosition(of: speaker) ?? triggerPosition()
                )
                speech.channels[speaker]?.playing = playback
                speech.lastError = nil
                startSpeakerLipSync(speaker, playback: playback, path: path)
            } catch {
                speech.lastError = "\(AudioLabCore.shortVoiceName(path)): \(error)"
                skip(speaker)
            }
        }
    }

    /// A file that cannot play does not end the line early: the next one plays.
    private func skip(_ speaker: ReferenceKey) {
        guard speech.channels[speaker]?.queue.pending.isEmpty == false else {
            // The line ended on a failure, so nothing played to its end.
            speech.channels[speaker] = nil
            return
        }
        advanceSpeech(speaker)
    }

    private func startSpeakerLipSync(
        _ speaker: ReferenceKey, playback: VoicePlayback, path: String
    ) {
        guard voice.lipSyncEnabled else { return }
        let started = startLipSync(
            playback: playback, path: path, on: world?.lipSyncTarget(for: speaker)
        )
        speech.channels[speaker]?.lip = started.driver
    }
}
