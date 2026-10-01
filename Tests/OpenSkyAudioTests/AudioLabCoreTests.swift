// The World > Audio picker, trigger, and readout rules, with plain values.

import Foundation
@testable import OpenSkyAudio
import OpenSkyGameData
import simd
import Testing

struct AudioLabCoreTests {
    private static let entries = [
        VFSEntry(path: "music\\b.xwm", archive: "a"),
        VFSEntry(path: "MUSIC\\A.XWM", archive: "a"),
        VFSEntry(path: "sound\\fx\\door.wav", archive: "a"),
        VFSEntry(path: "sound\\voice\\skyrim.esm\\malenord\\b.fuz", archive: "a"),
        VFSEntry(path: "sound\\voice\\skyrim.esm\\femaleeventoned\\a.fuz", archive: "a")
    ]

    private static func playback(duration: Double?, lipBytes: Int?) -> VoicePlayback {
        VoicePlayback(
            sourceID: 1,
            duration: duration,
            lipData: lipBytes.map { Data(count: $0) },
            clock: VoicePlaybackClock()
        )
    }

    @Test
    func musicPickerListsSortedXWMOnly() {
        #expect(AudioLabCore.musicPaths(in: Self.entries) == ["MUSIC\\A.XWM", "music\\b.xwm"])
    }

    @Test
    func voicePickerListsSortedFUZOnly() {
        #expect(AudioLabCore.voicePaths(in: Self.entries) == [
            "sound\\voice\\skyrim.esm\\femaleeventoned\\a.fuz",
            "sound\\voice\\skyrim.esm\\malenord\\b.fuz"
        ])
    }

    @Test
    func voiceFilterIgnoresCaseAndSlashDirection() {
        let paths = AudioLabCore.voicePaths(in: Self.entries)
        #expect(AudioLabCore.voiceMatches(in: paths, filter: "MaleNord/") == [
            "sound\\voice\\skyrim.esm\\malenord\\b.fuz"
        ])
        #expect(AudioLabCore.voiceMatches(in: paths, filter: "") == paths)
    }

    @Test
    func defaultFilterMatchesItsVoiceType() {
        let paths = AudioLabCore.voicePaths(in: Self.entries)
        #expect(AudioLabCore.voiceMatches(in: paths, filter: AudioLabCore.defaultVoiceFilter) == [
            "sound\\voice\\skyrim.esm\\femaleeventoned\\a.fuz"
        ])
    }

    @Test
    func triggerLandsAheadOfTheCamera() {
        let position = AudioLabCore.triggerPosition(camera: SIMD3(10, 20, 30), yaw: 0)
        #expect(simd_distance(position, SIMD3(710, 20, 30)) < 1e-3)
    }

    @Test
    func shortNameKeepsVoiceTypeAndFile() {
        #expect(AudioLabCore.shortVoiceName("sound\\voice\\skyrim.esm\\malenord\\b.fuz")
            == "malenord\\b.fuz")
    }

    @Test
    func voiceDescriptionNamesLengthAndLipData() {
        let path = "sound\\voice\\skyrim.esm\\malenord\\b.fuz"
        #expect(AudioLabCore.voiceDescription(
            path: path, playback: Self.playback(duration: 3.1, lipBytes: 12)
        ) == "malenord\\b.fuz — 3.10 s, 12 lip bytes")
        #expect(AudioLabCore.voiceDescription(
            path: path, playback: Self.playback(duration: nil, lipBytes: nil)
        ) == "malenord\\b.fuz — unknown length, no lip data")
    }

    @Test
    func playbackDescriptionCoversEveryState() {
        let line = Self.playback(duration: 3.1, lipBytes: nil)
        #expect(AudioLabCore.playbackDescription(playback: line, finished: true, position: 1)
            == "Position: finished at 3.10 s")
        #expect(AudioLabCore.playbackDescription(playback: line, finished: false, position: nil)
            == "Position: no reading (source retired or not yet rendering)")
        #expect(AudioLabCore.playbackDescription(playback: line, finished: false, position: 1.42)
            == "Position: 1.42 / 3.10 s")
        let unknown = Self.playback(duration: nil, lipBytes: nil)
        #expect(AudioLabCore.playbackDescription(playback: unknown, finished: false, position: 0.5)
            == "Position: 0.50 / ? s")
    }
}
