// Voice bridges of the shared main-app provider fake (item 17.5). Split out of
// FakeWorldProviders.swift, which is at the lint type-length cap; the state
// lives there in one `FakeVoiceState` value because an extension cannot hold
// stored properties.
//
// The fake mirrors the live bridge's shape rather than simplifying it: it holds
// the whole corpus, narrows it by the filter, and lists a bounded prefix of the
// matches, so a panel test exercises the truncation the real picker does.

import AppKit
@testable import opensky

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
        Array(matchedVoiceFilePaths.prefix(VoiceLabState.pickerLimit))
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
