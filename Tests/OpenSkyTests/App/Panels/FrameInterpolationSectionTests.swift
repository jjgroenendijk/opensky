// Developer > Rendering Performance > Frame Interpolation: the switch, the frame-rate
// readout, and the reason it cannot run.

import AppKit
@testable import OpenSky
@testable import OpenSkyRendering
import Testing

@MainActor
struct FrameInterpolationSectionTests {
    private static func section(
        _ providers: FakeWorldProviders, status: FrameInterpolationStatus
    ) -> FrameInterpolationSection {
        var snapshot = RenderPerformanceSnapshot()
        snapshot.frameInterpolation = status
        providers.renderPerformanceSnapshot = snapshot
        let section = FrameInterpolationSection()
        section.provider = providers
        section.loadViewIfNeeded()
        section.refreshReadout()
        return section
    }

    @Test
    func theSwitchReachesTheProviderAndCountsAsAnOverride() {
        let providers = FakeWorldProviders()
        let section = Self.section(providers, status: FrameInterpolationStatus())
        let control = section.enabledControl
        #expect(control.accessibilityIdentifier() == "FrameInterpolationControl")
        #expect(control.isEnabled)
        #expect(!FrameInterpolationSection.isOverridden(provider: providers))
        control.state = .on
        control.sendAction(control.action, to: section)
        #expect(providers.frameInterpolationEnabled)
        #expect(FrameInterpolationSection.isOverridden(provider: providers))
        FrameInterpolationSection.resetToDefaults(provider: providers)
        #expect(!providers.frameInterpolationEnabled)
    }

    @Test
    func theReadoutShowsRealAndShownFrameRates() {
        let providers = FakeWorldProviders()
        providers.frameInterpolationEnabled = true
        let section = Self.section(providers, status: FrameInterpolationStatus(
            enabled: true, interpolatedFrames: 42, realFPS: 30, presentLatencyMS: 51.25
        ))
        #expect(section.statsReadout == """
        Frame interpolation: on, 42 frames built
        Real: 30 fps  Shown: 60 fps
        Input to screen: 51.2 ms
        """)
    }

    @Test
    func anUnsupportedGPUDisablesTheSwitchAndSaysWhy() {
        let providers = FakeWorldProviders()
        providers.frameInterpolationEnabled = true
        let section = Self.section(providers, status: FrameInterpolationStatus(
            enabled: true, unsupportedReason: "This GPU has no MetalFX frame interpolator"
        ))
        #expect(!section.enabledControl.isEnabled)
        #expect(section.enabledControl.state == .off)
        #expect(section.statsReadout == """
        Frame interpolation: unavailable
        This GPU has no MetalFX frame interpolator
        """)
    }

    @Test
    func withoutTheTemporalUpscalerTheReadoutSaysWhatItNeeds() {
        let providers = FakeWorldProviders()
        let section = Self.section(providers, status: FrameInterpolationStatus(
            enabled: true, unavailableReason: "Needs the temporal upscaler: pick a render scale",
            realFPS: 60
        ))
        #expect(section.statsReadout.hasSuffix("Needs the temporal upscaler: pick a render scale"))
    }
}
