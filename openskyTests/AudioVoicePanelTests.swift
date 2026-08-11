// World > Audio > Voice verification surface (item 17.5): control geometry,
// the literal accessibility-id contract, the filter/picker round-trip and the
// readout wording — including the one thing a truncated picker must never do,
// which is read as though it listed everything that matched.

import AppKit
@testable import opensky
import Testing

struct AudioVoicePanelTests {
    @Test @MainActor
    func controlsHaveVisibleFramesInsideDocument() throws {
        let panel = AudioPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 900)
        panel.view.layoutSubtreeIfNeeded()
        let controls: [NSView] = [
            panel.audioVoiceFilterControl,
            panel.audioVoiceFileControl,
            panel.audioVoicePlayControl,
            panel.lipSyncEnabledControl
        ]
        for control in controls {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
            let documentFrame = control.convert(control.bounds, to: scrollView.documentView)
            #expect(scrollView.documentView?.bounds.intersects(documentFrame) == true)
        }
    }

    @Test @MainActor
    func accessibilityIdentifiersArePinned() {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        #expect(panel.voiceSection.sectionIdentifier == "audioVoice")
        #expect(
            panel.audioVoiceFilterControl.accessibilityIdentifier()
                == "AudioVoiceFilterControl"
        )
        #expect(
            panel.voiceSection.applyFilterControl.accessibilityIdentifier()
                == "AudioVoiceFilterApplyControl"
        )
        #expect(panel.audioVoiceFileControl.accessibilityIdentifier() == "AudioVoiceFileControl")
        #expect(panel.audioVoicePlayControl.accessibilityIdentifier() == "AudioVoicePlayControl")
        #expect(panel.lipSyncEnabledControl.accessibilityIdentifier() == "LipSyncEnabledControl")
        #expect(
            panel.voiceSection.lipSyncReadout.accessibilityIdentifier()
                == "LipSyncStatsLabel"
        )
        #expect(panel.voiceSection.lipSyncReadout.isAccessibilityElement())
        #expect(panel.voiceSection.lipSyncReadout.accessibilityRole() == .group)
        #expect(panel.voiceSection.lipSyncReadout.accessibilityLabel() == "Lip sync status")
    }

    @Test @MainActor
    func pickerListsTheProvidersMatchesAndPlayingReachesTheProvider() {
        let panel = AudioPanelViewController()
        let provider = FakeAudioProvider()
        provider.selectableVoiceFileNames = [
            "sound\\voice\\skyrim.esm\\femaleeventoned\\wigreeting__000c7917_1.fuz",
            "sound\\voice\\skyrim.esm\\femaleeventoned\\wigreeting__000c7918_1.fuz"
        ]
        panel.provider = provider
        panel.loadViewIfNeeded()
        panel.voiceSection.syncControls()
        #expect(panel.audioVoiceFileControl.itemTitles == provider.selectableVoiceFileNames)
        panel.audioVoiceFileControl.selectItem(at: 1)
        panel.audioVoicePlayControl.performClick(nil)
        #expect(provider.playedVoiceFiles == [provider.selectableVoiceFileNames[1]])
    }

    @Test @MainActor
    func applyingTheFilterPushesItToTheProvider() {
        let panel = AudioPanelViewController()
        let provider = FakeAudioProvider()
        panel.provider = provider
        panel.loadViewIfNeeded()
        panel.audioVoiceFilterControl.stringValue = "malenord"
        panel.voiceSection.applyFilterControl.performClick(nil)
        #expect(provider.voiceFileFilter == "malenord")
    }

    @Test @MainActor
    func lipSyncToggleAndReadoutReachTheProvider() {
        let panel = AudioPanelViewController()
        let provider = FakeAudioProvider()
        provider.lipSyncSnapshot = LipSyncSnapshot(
            actor: FormID(0x14),
            activeLine: "femaleeventoned\\line.fuz",
            trackTime: 0.5,
            clockMode: .audio,
            liveWeights: ["Aah": 0.75],
            unmappedActiveSlots: [31],
            isDecaying: false
        )
        panel.provider = provider
        panel.loadViewIfNeeded()
        panel.voiceSection.refreshReadout()

        panel.lipSyncEnabledControl.performClick(nil)
        #expect(!provider.lipSyncEnabled)
        #expect(panel.voiceSection.isOverridden)
        #expect(panel.voiceSection.lipSyncStatsLabel.stringValue.contains("Aah 0.75"))
        #expect(panel.voiceSection.lipSyncStatsLabel.stringValue.contains("Unmapped slots: 31"))

        panel.voiceSection.performResetToDefaults()
        #expect(provider.lipSyncEnabled)
    }

    @Test @MainActor
    func readoutStatesTheTrueMatchCountBesideTheListedOne() {
        let text = AudioVoiceSection.readoutText(
            listed: 200,
            matched: 34818,
            line: "femaleeventoned\\wigreeting__000c7917_1.fuz — 3.10 s, 1728 lip bytes",
            playback: "Position: 1.42 / 3.10 s",
            error: nil
        )
        #expect(text.contains("200 listed of 34818 matching"))
        #expect(text.contains("Position: 1.42 / 3.10 s"))
        #expect(!text.contains("Play failed"))
    }

    @Test @MainActor
    func readoutStatesWhyNothingPlayed() {
        let text = AudioVoiceSection.readoutText(
            listed: 0, matched: 0, line: nil, playback: "", error: "audio engine is not running"
        )
        #expect(text.contains("none played yet"))
        #expect(text.contains("Play failed: audio engine is not running"))
    }
}
