// The launcher's Graphics page: its pinned ids, its defaults, and that each switch saves
// the setting the game reads when it starts.

import AppKit
@testable import OpenSky
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld
import Testing

@MainActor
struct GraphicsPageTests {
    private func makePage(
        store: PlayerSettingsStore = PlayerSettingsStore(persistence: nil),
        rayTracing: RayTracingAvailability = .unavailable(
            reason: RayTracingAvailability.softwareReason
        )
    ) -> GraphicsPageViewController {
        let page = GraphicsPageViewController(reloadStore: { store }, rayTracing: rayTracing)
        page.loadViewIfNeeded()
        return page
    }

    @Test func idsArePinned() {
        let page = makePage()
        #expect(page.pipelineCacheControl
            .accessibilityIdentifier() == "GraphicsPipelineCacheControl")
        #expect(
            page.clearPipelineCacheControl.accessibilityIdentifier()
                == "GraphicsPipelineCacheClearControl"
        )
        #expect(page.gpuCullingControl.accessibilityIdentifier() == "GraphicsGPUCullingControl")
        #expect(
            page.textureStreamingControl.accessibilityIdentifier()
                == "GraphicsTextureStreamingControl"
        )
        #expect(
            page.textureBudgetControl.accessibilityIdentifier() == "GraphicsTextureBudgetControl"
        )
        #expect(page.statusLabel.accessibilityIdentifier() == "GraphicsStatsLabel")
    }

    @Test func everyFeatureStartsOn() {
        let page = makePage()
        #expect(page.pipelineCacheControl.state == .on)
        #expect(page.gpuCullingControl.state == .on)
        #expect(page.textureStreamingControl.state == .on)
        #expect(page.textureBudgetControl.titleOfSelectedItem == "Budget 512 MiB")
    }

    @Test func eachSwitchSavesItsSetting() {
        let store = PlayerSettingsStore(persistence: nil)
        let page = makePage(store: store)
        page.gpuCullingControl.state = .off
        page.gpuCullingControl.sendAction(page.gpuCullingControl.action, to: page)
        #expect(!store.bool(.gpuCulling))
        page.pipelineCacheControl.state = .off
        page.pipelineCacheControl.sendAction(page.pipelineCacheControl.action, to: page)
        #expect(!store.bool(.pipelineCacheEnabled))
        page.textureStreamingControl.state = .off
        page.textureStreamingControl.sendAction(page.textureStreamingControl.action, to: page)
        #expect(!store.bool(.textureStreaming))
        page.textureBudgetControl.selectItem(at: 4)
        page.textureBudgetControl.sendAction(page.textureBudgetControl.action, to: page)
        #expect(store.value(.textureBudget) == 4)
    }

    @Test func showingThePageReadsTheSettingsAgain() {
        let store = PlayerSettingsStore(persistence: nil)
        let page = makePage(store: store)
        store.set(.gpuCulling, to: 0)
        page.viewWillAppear()
        #expect(page.gpuCullingControl.state == .off)
    }

    @Test func rayTracingShowsWhyItIsOff() {
        let page = makePage()
        #expect(
            page.rayTracedShadowsControl.accessibilityIdentifier()
                == "GraphicsRayTracedShadowsControl"
        )
        #expect(page.rayTracingLabel.accessibilityIdentifier() == "GraphicsRayTracingLabel")
        #expect(!page.rayTracedShadowsControl.isEnabled)
        #expect(page.rayTracedShadowsControl.state == .off)
        #expect(page.rayTracingLabel.stringValue.hasPrefix("Unavailable: "))
    }

    @Test func anAvailableGPUSavesTheRayTracingSwitch() {
        let store = PlayerSettingsStore(persistence: nil)
        let page = makePage(store: store, rayTracing: .available)
        #expect(page.rayTracedShadowsControl.isEnabled)
        #expect(page.rayTracingLabel.stringValue.isEmpty)
        page.rayTracedShadowsControl.state = .on
        page.rayTracedShadowsControl.sendAction(page.rayTracedShadowsControl.action, to: page)
        #expect(store.bool(.rayTracedShadows))
    }

    @Test func upscalingStartsOffAndSavesItsChoices() {
        let store = PlayerSettingsStore(persistence: nil)
        let page = makePage(store: store)
        #expect(page.renderScaleControl.accessibilityIdentifier() == "GraphicsRenderScaleControl")
        #expect(page.upscalerControl.accessibilityIdentifier() == "GraphicsUpscalerControl")
        #expect(page.renderScaleControl.titleOfSelectedItem == "Render scale Off")
        page.renderScaleControl.selectItem(withTitle: "Render scale 67%")
        page.renderScaleControl.sendAction(page.renderScaleControl.action, to: page)
        #expect(RenderScale(store: store) == RenderScale(percent: 67))
        page.upscalerControl.selectItem(withTitle: "Spatial")
        page.upscalerControl.sendAction(page.upscalerControl.action, to: page)
        #expect(UpscalerKind(store: store) == .spatial)
    }
}
