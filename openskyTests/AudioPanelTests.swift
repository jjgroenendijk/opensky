// World > Audio verification-surface coverage: control geometry inside the
// scroll document, the literal accessibility-id contract, and provider
// round-trips (enable checkbox, volume sliders, positional trigger).

import AppKit
@testable import opensky
import Testing

@MainActor
private final class FakeAudioProvider: AudioControlProviding {
    var audioEnabled = false
    var audioMasterVolume: Float = 1
    private var categoryVolumes: [AudioCategory: Float] = [:]
    var selectableAudioFileNames: [String] = []
    var playedFiles: [String] = []
    var stopAllCount = 0
    var audioStatsSnapshot = AudioStatsSnapshot.empty

    func audioVolume(for category: AudioCategory) -> Float {
        categoryVolumes[category] ?? 1
    }

    func setAudioVolume(_ volume: Float, for category: AudioCategory) {
        categoryVolumes[category] = volume
    }

    func playAudioFile(named name: String) -> String? {
        playedFiles.append(name)
        return nil
    }

    func stopAllAudioSources() {
        stopAllCount += 1
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
            panel.audioStopAllControl
        ] + panel.outputSection.categoryControls.values.map(\.self)
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
            "AudioAmbienceVolumeControl", "AudioEffectsVolumeControl",
            "AudioMusicVolumeControl"
        ])
        #expect(panel.outputSection.sectionIdentifier == "audioOutput")
        #expect(panel.sourcesSection.sectionIdentifier == "audioSources")
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
}
