// Developer > Rendering Performance > Upscaling: the render-scale and upscaler pop-ups
// and the size readout.

import AppKit
@testable import OpenSky
@testable import OpenSkyRendering
import Testing

@MainActor
struct UpscalingSectionTests {
    @Test
    func thePopUpReachesTheProviderAndCountsAsAnOverride() {
        let providers = FakeWorldProviders()
        let section = UpscalingSection()
        section.provider = providers
        section.loadViewIfNeeded()
        #expect(section.scaleControl.accessibilityIdentifier() == "RenderScaleControl")
        #expect(section.scaleControl.numberOfItems == RenderScale.percentOptions.count)
        #expect(!UpscalingSection.isOverridden(provider: providers))

        section.scaleControl.selectItem(withTitle: "67%")
        section.scaleControl.sendAction(section.scaleControl.action, to: section)
        #expect(providers.renderScale == RenderScale(percent: 67))
        #expect(UpscalingSection.isOverridden(provider: providers))
        #expect(section.upscalerControl.accessibilityIdentifier() == "UpscalerControl")
        section.upscalerControl.selectItem(withTitle: "Spatial")
        section.upscalerControl.sendAction(section.upscalerControl.action, to: section)
        #expect(providers.upscaler == .spatial)
        UpscalingSection.resetToDefaults(provider: providers)
        #expect(providers.renderScale == .off)
        #expect(providers.upscaler == .temporal)
    }

    @Test
    func theReadoutShowsTheSizesOrWhyItIsOff() {
        let providers = FakeWorldProviders()
        providers.renderScale = RenderScale(percent: 67)
        var snapshot = RenderPerformanceSnapshot()
        snapshot.upscaling = UpscaleStatus(
            inputSize: SIMD2(1715, 1072), outputSize: SIMD2(2560, 1600), historyResets: 3
        )
        providers.renderPerformanceSnapshot = snapshot
        let section = UpscalingSection()
        section.provider = providers
        section.loadViewIfNeeded()
        section.refreshReadout()
        #expect(section.statsReadout == """
        Upscaling: 67%, temporal
        Scene: 1715 x 1072  Output: 2560 x 1600
        History resets: 3
        """)

        snapshot.upscaling = UpscaleStatus(
            unavailableReason: "This GPU has no MetalFX temporal scaler"
        )
        providers.renderPerformanceSnapshot = snapshot
        section.refreshReadout()
        #expect(section.statsReadout.hasPrefix("Upscaling: unavailable"))
    }
}
