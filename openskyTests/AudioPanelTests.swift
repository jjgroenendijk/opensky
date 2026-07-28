// World > Audio verification-surface coverage: control geometry inside the
// scroll document, the literal accessibility-id contract, and provider
// round-trips (enable checkbox, volume sliders, positional trigger).

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

struct AudioPanelTests {
    @Test @MainActor
    func controlsHaveVisibleFramesInsideDocument() throws {
        let panel = AudioPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        panel.view.layoutSubtreeIfNeeded()

        let controls: [NSView] = [
            panel.audioEnabledControl,
            panel.audioMasterVolumeControl,
            panel.audioFileControl,
            panel.audioPlaySelectedControl,
            panel.audioStopAllControl,
            panel.audioMusicEnabledControl,
            panel.audioMusicTypeControl,
            panel.audioStopMusicControl
        ] + panel.outputSection.categoryControls.values.map(\.self)
            + panel.outputSection.muteControls.values.map(\.self)
            + panel.outputSection.soloControls.values.map(\.self)
        for control in controls {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
            let documentFrame = control.convert(control.bounds, to: scrollView.documentView)
            #expect(scrollView.documentView?.bounds.intersects(documentFrame) == true)
        }
    }

    /// Accessibility ids are the UI-test API (docs/tools/app-ui.md); pin the
    /// audio set literally.
    @Test @MainActor
    func accessibilityIdentifiersArePinned() {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        #expect(panel.audioEnabledControl.accessibilityIdentifier() == "AudioEnabledControl")
        #expect(
            panel.audioMasterVolumeControl.accessibilityIdentifier()
                == "AudioMasterVolumeControl"
        )
        #expect(panel.audioFileControl.accessibilityIdentifier() == "AudioFileControl")
        #expect(
            panel.audioPlaySelectedControl.accessibilityIdentifier()
                == "AudioPlaySelectedControl"
        )
        #expect(panel.audioStopAllControl.accessibilityIdentifier() == "AudioStopAllControl")
        let categoryIDs = panel.outputSection.categoryControls.values
            .map { $0.accessibilityIdentifier() }.sorted()
        #expect(categoryIDs == [
            "AudioEffectsVolumeControl", "AudioFootstepsVolumeControl",
            "AudioMusicVolumeControl", "AudioVoiceVolumeControl"
        ])
        // M9.2.4 per-category mute + solo pins.
        let muteIDs = panel.outputSection.muteControls.values
            .map { $0.accessibilityIdentifier() }.sorted()
        #expect(muteIDs == [
            "AudioEffectsMuteControl", "AudioFootstepsMuteControl",
            "AudioMusicMuteControl", "AudioVoiceMuteControl"
        ])
        let soloIDs = panel.outputSection.soloControls.values
            .map { $0.accessibilityIdentifier() }.sorted()
        #expect(soloIDs == [
            "AudioEffectsSoloControl", "AudioFootstepsSoloControl",
            "AudioMusicSoloControl", "AudioVoiceSoloControl"
        ])
        #expect(panel.outputSection.sectionIdentifier == "audioOutput")
        #expect(panel.sourcesSection.sectionIdentifier == "audioSources")
        // M9.2.2 SFX + ambience section pins.
        #expect(panel.sfxSection.sectionIdentifier == "audioSfx")
        #expect(
            panel.sfxSection.sfxEnabledControl.accessibilityIdentifier()
                == "AudioSfxEnabledControl"
        )
        #expect(
            panel.sfxSection.ambienceEnabledControl.accessibilityIdentifier()
                == "AudioAmbienceEnabledControl"
        )
        #expect(
            panel.sfxSection.stopAmbienceControl.accessibilityIdentifier()
                == "AudioStopAmbienceControl"
        )
        // M9.2.3 music playlist section pins.
        #expect(panel.musicSection.sectionIdentifier == "audioMusic")
        #expect(
            panel.audioMusicEnabledControl.accessibilityIdentifier()
                == "AudioMusicEnabledControl"
        )
        #expect(panel.audioMusicTypeControl.accessibilityIdentifier() == "AudioMusicTypeControl")
        #expect(panel.audioStopMusicControl.accessibilityIdentifier() == "AudioStopMusicControl")
    }

    @Test @MainActor
    func enableCheckboxRoundTripsProviderState() {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeAudioProvider()
        fake.audioEnabled = false
        panel.provider = fake

        #expect(panel.audioEnabledControl.state == .off)
        panel.audioEnabledControl.state = .on
        panel.audioEnabledControl.sendAction(
            panel.audioEnabledControl.action, to: panel.audioEnabledControl.target
        )
        #expect(fake.audioEnabled == true)
    }

    @Test @MainActor
    func playTriggersSelectedFile() {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeAudioProvider()
        fake.selectableAudioFileNames = ["music\\a.xwm", "music\\b.xwm"]
        panel.provider = fake

        panel.audioFileControl.selectItem(withTitle: "music\\b.xwm")
        panel.audioPlaySelectedControl.sendAction(
            panel.audioPlaySelectedControl.action, to: panel.audioPlaySelectedControl.target
        )
        #expect(fake.playedFiles == ["music\\b.xwm"])

        panel.audioStopAllControl.sendAction(
            panel.audioStopAllControl.action, to: panel.audioStopAllControl.target
        )
        #expect(fake.stopAllCount == 1)
    }

    @Test @MainActor
    func categorySliderDrivesProviderVolume() {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeAudioProvider()
        panel.provider = fake

        let slider = panel.outputSection.categoryControls[.music]
        slider?.floatValue = 0.4
        if let slider {
            slider.sendAction(slider.action, to: slider.target)
        }
        #expect(abs(fake.audioVolume(for: .music) - 0.4) < 1e-5)
        #expect(abs(fake.audioVolume(for: .effects) - 1) < 1e-5)
    }

    @Test @MainActor
    func sfxSectionRoundTripsProviderState() {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeAudioProvider()
        panel.provider = fake

        // Both default on; toggle SFX off through the checkbox.
        #expect(panel.sfxSection.sfxEnabledControl.state == .on)
        panel.sfxSection.sfxEnabledControl.state = .off
        panel.sfxSection.sfxEnabledControl.sendAction(
            panel.sfxSection.sfxEnabledControl.action,
            to: panel.sfxSection.sfxEnabledControl.target
        )
        #expect(fake.sfxEnabled == false)

        // Ambience toggle and stop button exercise the same path.
        panel.sfxSection.ambienceEnabledControl.state = .off
        panel.sfxSection.ambienceEnabledControl.sendAction(
            panel.sfxSection.ambienceEnabledControl.action,
            to: panel.sfxSection.ambienceEnabledControl.target
        )
        #expect(fake.ambienceEnabled == false)

        panel.sfxSection.stopAmbienceControl.sendAction(
            panel.sfxSection.stopAmbienceControl.action,
            to: panel.sfxSection.stopAmbienceControl.target
        )
        #expect(fake.stopAmbienceCount == 1)
    }

    /// M9.2.3: the picker offers the automatic entry plus the provider's MUSC
    /// list, and forcing an entry reaches the director.
    @Test @MainActor
    func musicPickerForcesTheSelectedPlaylist() {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeAudioProvider()
        fake.selectableMusicTypeNames = ["MUSDungeon", "MUSExplore"]
        panel.provider = fake

        #expect(panel.audioMusicTypeControl.itemTitles == [
            AudioMusicSection.automaticTitle, "MUSDungeon", "MUSExplore"
        ])
        #expect(panel.audioMusicTypeControl.titleOfSelectedItem
            == AudioMusicSection.automaticTitle)

        panel.audioMusicTypeControl.selectItem(withTitle: "MUSExplore")
        panel.audioMusicTypeControl.sendAction(
            panel.audioMusicTypeControl.action, to: panel.audioMusicTypeControl.target
        )
        #expect(fake.forcedMusicTypeNames == ["MUSExplore"])
        #expect(panel.musicSection.forcedTypeName == "MUSExplore")

        // Back to automatic: no new force, and the director is told to stop so
        // the next streamed cell resolves the playlist itself.
        panel.audioMusicTypeControl.selectItem(withTitle: AudioMusicSection.automaticTitle)
        panel.audioMusicTypeControl.sendAction(
            panel.audioMusicTypeControl.action, to: panel.audioMusicTypeControl.target
        )
        #expect(fake.forcedMusicTypeNames == ["MUSExplore"])
        #expect(fake.stopMusicCount == 1)
        #expect(panel.musicSection.forcedTypeName == nil)
    }

    @Test @MainActor
    func musicToggleAndStopReachTheProvider() {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeAudioProvider()
        panel.provider = fake

        #expect(panel.audioMusicEnabledControl.state == .on)
        panel.audioMusicEnabledControl.state = .off
        panel.audioMusicEnabledControl.sendAction(
            panel.audioMusicEnabledControl.action, to: panel.audioMusicEnabledControl.target
        )
        #expect(fake.musicEnabled == false)

        panel.audioStopMusicControl.sendAction(
            panel.audioStopMusicControl.action, to: panel.audioStopMusicControl.target
        )
        #expect(fake.stopMusicCount == 1)
    }

    @Test @MainActor
    func musicReadoutShowsStateDescriptionAndError() {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeAudioProvider()
        fake.currentMusicStateName = "interior"
        fake.currentMusicDescription = "MUSDungeon — music\\dungeon\\a.xwm"
        panel.provider = fake
        panel.musicSection.refreshReadout()

        var readout = Self.readout("AudioMusicStatsLabel", in: panel.view) ?? ""
        #expect(readout.contains("State: interior"))
        #expect(readout.contains("Music: MUSDungeon — music\\dungeon\\a.xwm"))
        #expect(!readout.contains("Music error"))

        fake.lastMusicError = "missing track"
        panel.musicSection.refreshReadout()
        readout = Self.readout("AudioMusicStatsLabel", in: panel.view) ?? ""
        #expect(readout.contains("Music error: missing track"))
    }

    /// A forced playlist and a disabled director are both overrides; reset
    /// clears each and hands selection back to the precedence chain.
    @Test @MainActor
    func musicOverrideStateTracksForceAndEnable() {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeAudioProvider()
        fake.selectableMusicTypeNames = ["MUSExplore"]
        panel.provider = fake
        #expect(!panel.musicSection.isOverridden)

        panel.audioMusicTypeControl.selectItem(withTitle: "MUSExplore")
        panel.audioMusicTypeControl.sendAction(
            panel.audioMusicTypeControl.action, to: panel.audioMusicTypeControl.target
        )
        #expect(panel.musicSection.isOverridden)

        fake.musicEnabled = false
        #expect(AudioMusicSection.isOverridden(provider: fake))

        panel.musicSection.performResetToDefaults()
        #expect(fake.musicEnabled)
        #expect(panel.musicSection.forcedTypeName == nil)
        #expect(!panel.musicSection.isOverridden)
        #expect(panel.audioMusicTypeControl.titleOfSelectedItem
            == AudioMusicSection.automaticTitle)
    }

    /// Depth-first search for a readout label's text, mirroring the acceptance
    /// harness helper.
    private static func readout(_ identifier: String, in view: NSView) -> String? {
        if view.accessibilityIdentifier() == identifier, let field = view as? NSTextField {
            return field.stringValue
        }
        for subview in view.subviews {
            if let found = readout(identifier, in: subview) {
                return found
            }
        }
        return nil
    }
}
