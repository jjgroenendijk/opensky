// The audio control fake, shared by every suite that drives World > Audio and by
// the real-data footstep suite in openskyRealDataTests. It lives here rather than
// beside one suite because openskyTestSupport is the folder both test targets
// compile; see openskyTestSupport/AGENTS.md.

import AppKit
@testable import opensky
import Testing

/// Shared with the M9.2.4 mute/solo satellite file
/// (`AudioPanelMuteSoloTests.swift`), so it is internal rather than private.
@MainActor
final class FakeAudioProvider: AudioControlProviding {
    var audioEnabled = false
    var audioMasterVolume: Float = 1
    private var categoryVolumes: [AudioCategory: Float] = [:]
    private var mutedCategories: Set<AudioCategory> = []
    var soloedAudioCategory: AudioCategory?
    var selectableAudioFileNames: [String] = []
    var playedFiles: [String] = []
    var stopAllCount = 0
    var audioStatsSnapshot = AudioStatsSnapshot.empty

    var sfxEnabled = true
    var ambienceEnabled = true
    var stopAmbienceCount = 0
    var lastSFXDescription: String?
    var lastSFXError: String?
    var currentAmbienceDescription = "none"

    var musicEnabled = true
    var selectableMusicTypeNames: [String] = []
    var forcedMusicTypeNames: [String] = []
    var stopMusicCount = 0
    var currentMusicDescription = "none"
    var currentMusicStateName = "exploration"
    var currentMusicTrackName: String?
    var lastMusicError: String?

    /// Footstep director bridges (issue #352), delegated to the shared fake so
    /// both panel fakes record the same way; the forwarding conformance lives
    /// in `FakeFootstepControls.swift`.
    let footsteps = FakeFootstepControls()

    func audioVolume(for category: AudioCategory) -> Float {
        categoryVolumes[category] ?? 1
    }

    func setAudioVolume(_ volume: Float, for category: AudioCategory) {
        categoryVolumes[category] = volume
    }

    func audioCategoryIsMuted(_ category: AudioCategory) -> Bool {
        mutedCategories.contains(category)
    }

    func setAudioCategoryMuted(_ muted: Bool, for category: AudioCategory) {
        if muted {
            mutedCategories.insert(category)
        } else {
            mutedCategories.remove(category)
        }
    }

    func playAudioFile(named name: String) -> String? {
        playedFiles.append(name)
        return nil
    }

    func stopAllAudioSources() {
        stopAllCount += 1
    }

    func stopAmbience() {
        stopAmbienceCount += 1
    }

    func forceMusicType(named name: String) -> String? {
        forcedMusicTypeNames.append(name)
        return nil
    }

    func stopMusic() {
        stopMusicCount += 1
    }
}
