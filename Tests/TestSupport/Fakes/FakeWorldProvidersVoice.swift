// Voice bridges of the shared provider fake. State lives in `FakeVoiceState`
// in FakeWorldProviders.swift, because an extension cannot store it. The fake
// filters the whole corpus and lists a bounded prefix, like the real picker.

import AppKit
import OpenSkyAudio
@testable import OpenSkyWorld

@MainActor
struct FakeVoiceState {
    var filter = ""
    /// Every voice path the fake corpus holds; the picker lists the matches.
    var paths: [String] = []
    /// Files the Voice section asked to play, in order.
    var playedNames: [String] = []
    /// Failure the next `playVoiceFile(named:)` reports; nil means success.
    var playFailure: String?
    var currentDescription: String?
    var playbackDescription = ""
    var lastError: String?
    var lipSyncEnabled = true
    var lipSyncSnapshot = LipSyncSnapshot.empty
    var lastLipSyncError: String?
}

extension FakeWorldProviders {
    var voiceFileFilter: String {
        get { voice.filter }
        set { voice.filter = newValue }
    }

    var selectableVoiceFileNames: [String] {
        Array(matchedVoiceFilePaths.prefix(AudioLabCore.voicePickerLimit))
    }

    var voiceFileMatchCount: Int {
        matchedVoiceFilePaths.count
    }

    var currentVoiceDescription: String? {
        voice.currentDescription
    }

    var voicePlaybackDescription: String {
        voice.playbackDescription
    }

    var lastVoiceError: String? {
        voice.lastError
    }

    var lipSyncEnabled: Bool {
        get { voice.lipSyncEnabled }
        set { voice.lipSyncEnabled = newValue }
    }

    var lipSyncSnapshot: LipSyncSnapshot {
        voice.lipSyncSnapshot
    }

    var lastLipSyncError: String? {
        voice.lastLipSyncError
    }

    /// Files the Voice section asked to play, in order.
    var playedVoiceFileNames: [String] {
        voice.playedNames
    }

    func playVoiceFile(named name: String) -> String? {
        voice.playedNames.append(name)
        voice.lastError = voice.playFailure
        guard voice.playFailure == nil else { return voice.playFailure }
        voice.currentDescription = name
        return nil
    }

    private var matchedVoiceFilePaths: [String] {
        guard !voice.filter.isEmpty else { return voice.paths }
        return voice.paths.filter { $0.contains(voice.filter.lowercased()) }
    }
}
