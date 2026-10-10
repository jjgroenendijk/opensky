// The launcher's Graphics page: its pinned ids, its defaults, its presets, and that
// each switch saves the setting the game reads when it starts.

import AppKit
import Foundation
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
        ),
        interpolationUnsupportedReason: String? = nil,
        meshShaderUnsupportedReason: String? = nil,
        presets: GraphicsPresetFiles = GraphicsPresetFiles(files: [:])
    ) -> GraphicsPageViewController {
        let page = GraphicsPageViewController(
            reloadStore: { store }, reloadPresets: { presets }, rayTracing: rayTracing,
            interpolationUnsupportedReason: interpolationUnsupportedReason,
            meshShaderUnsupportedReason: meshShaderUnsupportedReason
        )
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
        #expect(page.presetControl.accessibilityIdentifier() == "GraphicsPresetControl")
        #expect(page.fullScreenControl.accessibilityIdentifier() == "GraphicsFullScreenControl")
        #expect(page.frameRateCapControl.accessibilityIdentifier() == "GraphicsFrameRateCapControl")
        #expect(page.optionRows.count == GraphicsOptions.all.count)
    }

    @Test func everyFeatureStartsOn() {
        let page = makePage()
        #expect(page.pipelineCacheControl.state == .on)
        #expect(page.gpuCullingControl.state == .on)
        #expect(page.textureStreamingControl.state == .on)
        #expect(page.textureBudgetControl.titleOfSelectedItem == "Automatic")
        #expect(page.textureBudgetLabel.stringValue.hasPrefix("Automatic: "))
        #expect(page.fullScreenControl.state == .off)
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
        #expect(page.textureBudgetLabel.stringValue.hasPrefix("Fixed: "))
        page.frameRateCapControl.selectItem(at: 2)
        page.frameRateCapControl.sendAction(page.frameRateCapControl.action, to: page)
        #expect(store.value(.frameRateCap) == 2)
    }

    /// Two keys of a preset file, written in code.
    private func presetFiles(near: String, trees: String) -> GraphicsPresetFiles {
        let text = "[TerrainManager]\nfBlockLevel0Distance=\(near)\nfTreeLoadDistance=\(trees)\n"
        return GraphicsPresetFiles(files: [
            .low: INIFile(data: Data(text.utf8)),
            .ultra: INIFile(data: Data(text.replacingOccurrences(of: near, with: "90000").utf8))
        ])
    }

    @Test func aPresetSetsItsValuesAndAChangeMakesItCustom() throws {
        let store = PlayerSettingsStore(persistence: nil)
        let page = makePage(store: store, presets: presetFiles(near: "20000", trees: "40000"))
        #expect(page.presetControl.isEnabled)
        #expect(page.presetControl.titleOfSelectedItem == "Custom")
        page.presetControl.selectItem(at: GraphicsPreset.low.rawValue)
        page.presetControl.sendAction(page.presetControl.action, to: page)
        let near = try #require(GraphicsOptions.all.first { $0.key == "fBlockLevel0Distance" })
        #expect(store.value(near.id) == 20000)
        #expect(store.value(.textureQuality) == GraphicsPreset.low.textureQualityIndex)
        #expect(page.presetControl.titleOfSelectedItem == "Low")
        page.set(near.id, to: 30000)
        #expect(page.presetControl.titleOfSelectedItem == "Custom")
    }

    @Test func withoutPresetFilesThePresetIsOffAndSaysWhy() {
        let page = makePage()
        #expect(!page.presetControl.isEnabled)
        #expect(page.presetLabel.stringValue.hasPrefix("Unavailable: "))
    }

    @Test func anUnavailableOptionIsOffAndSaysWhy() throws {
        let page = makePage()
        let row = try #require(page.optionRows.first { $0.option.unavailableReason != nil })
        let control = try #require(find(
            "GraphicsOption\(row.option.key)Control",
            in: row.view
        ) as? NSControl)
        #expect(!control.isEnabled)
        let note = try #require(find(
            "GraphicsOption\(row.option.key)StatsLabel",
            in: row.view
        ) as? NSTextField)
        #expect(note.stringValue.hasPrefix("Unavailable: "))
    }

    @Test func anAppliedDistanceSavesATypedNumber() throws {
        let store = PlayerSettingsStore(persistence: nil)
        let page = makePage(store: store)
        let row = try #require(page.optionRows.first { $0.option.key == "fTreeLoadDistance" })
        let field = try #require(find(
            "GraphicsOptionfTreeLoadDistanceControl",
            in: row.view
        ) as? NSTextField)
        field.stringValue = "55000"
        field.sendAction(field.action, to: field.target)
        #expect(store.value(row.option.id) == 55000)
        field.stringValue = "-3"
        field.sendAction(field.action, to: field.target)
        #expect(store.value(row.option.id) == 55000)
    }

    private func find(_ identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier {
            return view
        }
        return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
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

    @Test func frameInterpolationStartsOffAndSavesItsSwitch() {
        let store = PlayerSettingsStore(persistence: nil)
        let page = makePage(store: store)
        let control = page.frameInterpolationControl
        #expect(control.accessibilityIdentifier() == "GraphicsFrameInterpolationControl")
        #expect(control.state == .off)
        control.state = .on
        control.sendAction(control.action, to: page)
        #expect(store.bool(.frameInterpolation))
    }

    @Test func meshShaderGrassStartsOffAndSavesItsSwitch() {
        let store = PlayerSettingsStore(persistence: nil)
        let page = makePage(store: store)
        let control = page.meshShaderGrassControl
        #expect(control.accessibilityIdentifier() == "GraphicsMeshShaderGrassControl")
        #expect(control.state == .off)
        control.state = .on
        control.sendAction(control.action, to: page)
        #expect(store.bool(.meshShaderGrass))
        let unsupported = makePage(store: store, meshShaderUnsupportedReason: "No mesh shaders")
        #expect(!unsupported.meshShaderGrassControl.isEnabled)
        #expect(unsupported.meshShaderGrassControl.state == .off)
    }

    @Test func anUnsupportedGPUDisablesFrameInterpolation() {
        let store = PlayerSettingsStore(persistence: nil)
        store.set(.frameInterpolation, to: 1)
        let page = makePage(store: store, interpolationUnsupportedReason: "No interpolator")
        #expect(!page.frameInterpolationControl.isEnabled)
        #expect(page.frameInterpolationControl.state == .off)
        #expect(page.frameInterpolationControl.toolTip == "No interpolator")
    }
}
