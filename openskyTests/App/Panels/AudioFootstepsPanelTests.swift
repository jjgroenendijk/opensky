// World > Audio > Footsteps section (issue #352): accessibility-id pins,
// layout, the enable round trip, the tag picker, and the readout. Satellite of
// AudioPanelTests.swift, which is at the strict-lint type-body cap. Sidebar
// path and control ids: docs/engine/audio.md.

import AppKit
@testable import opensky
import Testing

@MainActor
struct AudioFootstepsPanelTests {
    /// Accessibility ids are the UI-test API (docs/tools/app-ui.md); pin the
    /// footstep set literally.
    @Test func accessibilityIdentifiersArePinned() {
        let panel = Self.panel()
        #expect(panel.footstepsSection.sectionIdentifier == "audioFootsteps")
        #expect(
            panel.audioFootstepsEnabledControl.accessibilityIdentifier()
                == "AudioFootstepsEnabledControl"
        )
        #expect(
            panel.audioFootstepTagControl.accessibilityIdentifier()
                == "AudioFootstepTagControl"
        )
        #expect(
            panel.audioFootstepMaterialControl.accessibilityIdentifier()
                == "AudioFootstepMaterialControl"
        )
        #expect(
            panel.audioPlayFootstepControl.accessibilityIdentifier()
                == "AudioPlayFootstepControl"
        )
    }

    @Test func controlsHaveVisibleFramesInsideDocument() throws {
        let panel = AudioPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 900)
        panel.view.layoutSubtreeIfNeeded()

        for control in [
            panel.audioFootstepsEnabledControl,
            panel.audioFootstepTagControl,
            panel.audioFootstepMaterialControl,
            panel.audioPlayFootstepControl
        ] as [NSView] {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
            let documentFrame = control.convert(control.bounds, to: scrollView.documentView)
            #expect(scrollView.documentView?.bounds.intersects(documentFrame) == true)
        }
    }

    @Test func enableCheckboxRoundTripsProviderState() {
        let fake = FakeAudioProvider()
        let panel = Self.panel(provider: fake)

        #expect(panel.audioFootstepsEnabledControl.state == .on)
        panel.audioFootstepsEnabledControl.state = .off
        panel.audioFootstepsEnabledControl.sendAction(
            panel.audioFootstepsEnabledControl.action,
            to: panel.audioFootstepsEnabledControl.target
        )

        #expect(fake.footstepsEnabled == false)
        #expect(AudioFootstepsSection.isOverridden(provider: fake))
        AudioFootstepsSection.resetToDefaults(provider: fake)
        #expect(fake.footstepsEnabled)
        #expect(!AudioFootstepsSection.isOverridden(provider: fake))
    }

    /// The picker follows the gait, so it is rebuilt on every sync and stays
    /// disabled while the current gait's list is empty.
    @Test func tagPickerFollowsTheProvidersCurrentGait() {
        let fake = FakeAudioProvider()
        let panel = Self.panel(provider: fake)
        #expect(panel.audioFootstepTagControl.itemTitles.isEmpty)
        #expect(!panel.audioFootstepTagControl.isEnabled)
        #expect(!panel.audioPlayFootstepControl.isEnabled)

        fake.footsteps.currentFootstepTags = ["FootLeft", "FootRight"]
        panel.footstepsSection.syncControls()

        #expect(panel.audioFootstepTagControl.itemTitles == ["FootLeft", "FootRight"])
        #expect(panel.audioFootstepTagControl.isEnabled)
        #expect(panel.audioPlayFootstepControl.isEnabled)
    }

    @Test func playButtonForcesTheSelectedTag() {
        let fake = FakeAudioProvider()
        let panel = Self.panel(provider: fake)
        fake.footsteps.currentFootstepTags = ["FootLeft", "FootRight"]
        panel.footstepsSection.syncControls()
        panel.audioFootstepTagControl.selectItem(withTitle: "FootRight")

        panel.audioPlayFootstepControl.sendAction(
            panel.audioPlayFootstepControl.action,
            to: panel.audioPlayFootstepControl.target
        )

        #expect(fake.footsteps.forcedFootstepTags == ["FootRight"])
        #expect(fake.footstepCounts.played == 1)
    }

    @Test func readoutNamesTheSetTagsCountsAndErrors() {
        let fake = FakeAudioProvider()
        let panel = Self.panel(provider: fake)
        fake.footsteps.currentFootstepSetDescription = "FSTBarefootFootstepSet"
        fake.footsteps.currentFootstepTags = ["FootLeft"]
        fake.footsteps.footstepCounts = (routed: 7, played: 5)
        panel.footstepsSection.refreshReadout()

        var readout = Self.readout(in: panel.view) ?? ""
        #expect(readout.contains("Set: FSTBarefootFootstepSet"))
        #expect(readout.contains("Tags: FootLeft"))
        #expect(readout.contains("Routed 7, played 5"))

        fake.footsteps.lastFootstepError = "engine not running"
        panel.footstepsSection.refreshReadout()
        readout = Self.readout(in: panel.view) ?? ""
        #expect(readout.contains("Footstep error: engine not running"))
    }

    /// The material selector (issue #358): ground contact first, then every
    /// MATT the session carries, and picking one pins it on the provider.
    @Test func materialPickerPinsAMaterialAndResetClearsIt() {
        let fake = FakeAudioProvider()
        let panel = Self.panel(provider: fake)
        #expect(!panel.audioFootstepMaterialControl.isEnabled)

        fake.footsteps.footstepMaterialOptions = [
            (id: FormID(0x101), name: "MaterialSnow"),
            (id: FormID(0x102), name: "MaterialStone")
        ]
        panel.footstepsSection.syncControls()
        #expect(panel.audioFootstepMaterialControl.itemTitles == [
            "Ground contact", "MaterialSnow", "MaterialStone"
        ])
        #expect(panel.audioFootstepMaterialControl.indexOfSelectedItem == 0)

        panel.audioFootstepMaterialControl.selectItem(withTitle: "MaterialStone")
        panel.audioFootstepMaterialControl.sendAction(
            panel.audioFootstepMaterialControl.action,
            to: panel.audioFootstepMaterialControl.target
        )
        #expect(fake.forcedFootstepMaterial == FormID(0x102))
        #expect(AudioFootstepsSection.isOverridden(provider: fake))

        AudioFootstepsSection.resetToDefaults(provider: fake)
        panel.footstepsSection.syncControls()
        #expect(fake.forcedFootstepMaterial == nil)
        #expect(panel.audioFootstepMaterialControl.indexOfSelectedItem == 0)
    }

    @Test func readoutNamesTheSurfaceMaterial() {
        let fake = FakeAudioProvider()
        let panel = Self.panel(provider: fake)
        fake.footsteps.groundFootstepMaterialDescription = "MaterialSnow"
        panel.footstepsSection.refreshReadout()

        #expect(Self.readout(in: panel.view)?.contains("Material: MaterialSnow") == true)
    }

    @Test func readoutSaysUnavailableWithoutAProvider() {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        panel.footstepsSection.refreshReadout()

        #expect(Self.readout(in: panel.view)?.contains("unavailable") == true)
    }

    // MARK: - Helpers

    private static func panel(
        provider: FakeAudioProvider? = nil
    ) -> AudioPanelViewController {
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        if let provider {
            panel.provider = provider
        }
        return panel
    }

    private static func readout(in view: NSView) -> String? {
        if
            let label = view as? NSTextField,
            label.accessibilityIdentifier() == "AudioFootstepsStatsLabel"
        {
            return label.stringValue
        }
        for subview in view.subviews {
            if let found = readout(in: subview) {
                return found
            }
        }
        return nil
    }
}
