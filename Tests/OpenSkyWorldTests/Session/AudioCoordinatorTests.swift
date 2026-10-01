// The audio coordinator's world reads and its behavior before audio is enabled.
// The engine is never started, so no audio device is touched.

import Foundation
import GameDataTesting
import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
@testable import OpenSkyWorld
import simd
import Testing

@MainActor
private final class FakeAudioWorld: AudioWorld {
    var audioWorldData: (any WorldDataProviding)?
    var audioFileSystem: (any GameFileSource)?
    var audioListenerPose: (position: SIMD3<Float>, yaw: Float) = (.zero, 0)
    var playerFeetArmatures: [FormID]?
    var playerGait: LocomotionGait?
    var playerFeetPosition: SIMD3<Float>?
    var audioAnimationTime: Float = 0

    func lipSyncTarget() -> LipSyncPlayback? {
        nil
    }

    func installAudio(
        engine _: WorldAudioEngine,
        music _: WorldMusicDirector,
        footsteps _: WorldAudioFootstepDirector
    ) {}
}

@MainActor
struct AudioCoordinatorTests {
    /// The coordinator holds the world `weak`, so a test keeps it alive.
    private static func makeCoordinator() -> (AudioCoordinator, FakeAudioWorld) {
        let world = FakeAudioWorld()
        world.audioFileSystem = InMemoryFileSource(files: [
            "music\\b.xwm": Data(),
            "music\\a.xwm": Data(),
            "sound\\voice\\skyrim.esm\\femaleeventoned\\a.fuz": Data(),
            "sound\\voice\\skyrim.esm\\malenord\\b.fuz": Data()
        ])
        let audio = AudioCoordinator()
        audio.attach(world: world)
        return (audio, world)
    }

    @Test
    func musicPickerReadsTheFileSystemOnce() {
        let (audio, world) = Self.makeCoordinator()
        #expect(audio.selectableAudioFileNames == ["music\\a.xwm", "music\\b.xwm"])
        world.audioFileSystem = InMemoryFileSource()
        #expect(audio.selectableAudioFileNames == ["music\\a.xwm", "music\\b.xwm"])
    }

    @Test
    func voicePickerFollowsTheFilter() {
        let (audio, world) = Self.makeCoordinator()
        defer { withExtendedLifetime(world) {} }
        #expect(audio.selectableVoiceFileNames == [
            "sound\\voice\\skyrim.esm\\femaleeventoned\\a.fuz"
        ])
        audio.voiceFileFilter = ""
        #expect(audio.voiceFileMatchCount == 2)
        audio.voiceFileFilter = "malenord"
        #expect(audio.selectableVoiceFileNames == ["sound\\voice\\skyrim.esm\\malenord\\b.fuz"])
    }

    @Test
    func triggerReadsTheListenerPose() {
        let (audio, world) = Self.makeCoordinator()
        world.audioListenerPose = (SIMD3(1, 2, 3), 0)
        #expect(simd_distance(audio.triggerPosition(), SIMD3(701, 2, 3)) < 1e-3)
    }

    @Test
    func playRefusesWithoutARunningEngine() {
        let (audio, _) = Self.makeCoordinator()
        #expect(audio.playAudioFile(named: "music\\a.xwm") == "audio engine is not running")
        #expect(audio.playVoiceFile(named: "x.fuz") == "audio engine is not running")
        #expect(audio.lastVoiceError == "audio engine is not running")
        #expect(audio.currentVoiceDescription == nil)
        #expect(audio.voicePlaybackDescription.isEmpty)
    }

    @Test
    func controlsReadDefaultsBeforeAudioIsEnabled() {
        let (audio, world) = Self.makeCoordinator()
        world.playerGait = .walk
        world.playerFeetPosition = .zero
        #expect(!audio.audioEnabled)
        #expect(audio.audioMasterVolume == 1)
        #expect(audio.sfxEnabled && audio.musicEnabled && audio.footstepsEnabled)
        #expect(audio.currentMusicStateName == "unknown")
        #expect(audio.currentFootstepTags.isEmpty)
        #expect(audio.footstepCounts.routed == 0 && audio.footstepCounts.played == 0)
        #expect(audio.forceMusicType(named: "MUSExplore") == "audio is not enabled")
        #expect(audio.forcePlayFootstep(tag: "FSTWalkLeft") == "audio is not enabled")
    }

    @Test
    func lipSyncToggleIsKeptWithoutAPlayback() {
        let (audio, _) = Self.makeCoordinator()
        #expect(audio.lipSyncEnabled)
        audio.lipSyncEnabled = false
        #expect(!audio.lipSyncEnabled)
        #expect(audio.lipSyncSnapshot == .empty)
    }
}
