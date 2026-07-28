// World > Audio mute and solo verification surface (M9.2.4): the per-category
// mute checkbox and solo control, their mutual exclusivity, the override/reset
// contract, and the `AudioStatsLabel` line that makes the state readable.
// Satellite of AudioPanelTests.swift, which owns `FakeAudioProvider` and the
// id/geometry pins; split out to stay inside the type-body-length limit.

import AppKit
@testable import opensky
import Testing

struct AudioPanelMuteSoloTests {
    /// M9.2.4: the mute checkbox drives the provider, and the state survives a
    /// resync from provider state.
    @Test @MainActor
    func muteCheckboxDrivesProviderState() throws {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeAudioProvider()
        panel.provider = fake

        let mute = try #require(panel.outputSection.muteControls[.effects])
        mute.state = .on
        mute.sendAction(mute.action, to: mute.target)
        #expect(fake.audioCategoryIsMuted(.effects))
        #expect(!fake.audioCategoryIsMuted(.music))

        mute.state = .off
        mute.sendAction(mute.action, to: mute.target)
        #expect(!fake.audioCategoryIsMuted(.effects))

        fake.setAudioCategoryMuted(true, for: .music)
        panel.outputSection.syncControls()
        #expect(panel.outputSection.muteControls[.music]?.state == .on)
    }

    /// Solo is mutually exclusive across categories, and clicking the soloed
    /// category clears solo entirely.
    @Test @MainActor
    func soloControlIsMutuallyExclusive() throws {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeAudioProvider()
        panel.provider = fake

        let music = try #require(panel.outputSection.soloControls[.music])
        let voice = try #require(panel.outputSection.soloControls[.voice])
        music.state = .on
        music.sendAction(music.action, to: music.target)
        #expect(fake.soloedAudioCategory == .music)
        #expect(voice.state == .off)

        voice.state = .on
        voice.sendAction(voice.action, to: voice.target)
        #expect(fake.soloedAudioCategory == .voice)
        #expect(music.state == .off, "picking a second category must clear the first")

        voice.state = .off
        voice.sendAction(voice.action, to: voice.target)
        #expect(fake.soloedAudioCategory == nil)
    }

    /// The acceptance readout: mute and solo state must be visible as text.
    @Test @MainActor
    func statsReadoutShowsMuteAndSoloState() {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeAudioProvider()
        panel.provider = fake
        panel.outputSection.refreshReadout()
        #expect(Self.readout("AudioStatsLabel", in: panel.view)?
            .contains("Mute: none  Solo: none") == true)

        fake.setAudioCategoryMuted(true, for: .music)
        fake.setAudioCategoryMuted(true, for: .effects)
        fake.soloedAudioCategory = .voice
        panel.outputSection.refreshReadout()
        #expect(Self.readout("AudioStatsLabel", in: panel.view)?
            .contains("Mute: Effects, Music  Solo: Voice") == true)
    }

    /// Mute and solo are destination overrides, and the section reset clears
    /// both along with the volumes.
    @Test @MainActor
    func muteAndSoloCountAsOverridesAndReset() {
        let fake = FakeAudioProvider()
        #expect(!AudioOutputSection.isOverridden(provider: fake))

        fake.setAudioCategoryMuted(true, for: .footsteps)
        #expect(AudioOutputSection.isOverridden(provider: fake))
        AudioOutputSection.resetToDefaults(provider: fake)
        #expect(!fake.audioCategoryIsMuted(.footsteps))

        fake.soloedAudioCategory = .music
        #expect(AudioOutputSection.isOverridden(provider: fake))
        AudioOutputSection.resetToDefaults(provider: fake)
        #expect(fake.soloedAudioCategory == nil)
        #expect(!AudioOutputSection.isOverridden(provider: fake))
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
