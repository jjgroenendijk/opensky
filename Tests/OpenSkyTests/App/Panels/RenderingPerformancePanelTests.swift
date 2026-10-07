// Developer > Rendering Performance: the registry-built panel, its pinned ids, and the
// readouts it renders from the provider. Changing an id updates these literals in the
// same commit (docs/tools/app-ui.md).

import AppKit
@testable import OpenSky
@testable import OpenSkyRendering
import Testing

@MainActor
struct RenderingPerformancePanelTests {
    private func makePanel(
        _ providers: FakeWorldProviders
    ) throws -> RenderingPerformancePanelViewController {
        let descriptor = try #require(
            DestinationRegistry.all.first { $0.id == "renderingPerformance" }
        )
        #expect(descriptor.section == .developer)
        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("Rendering Performance is not a world inspector")
            throw RenderingPerformancePanelTestError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? RenderingPerformancePanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }

    @Test
    func theSectionsCarryTheirPinnedIdentifiers() throws {
        let panel = try makePanel(FakeWorldProviders())
        #expect(
            panel.sections.map(\.sectionIdentifier)
                == [
                    "renderTargets", "pipelineCache", "gpuCulling", "textureStreaming",
                    "rayTracedShadows", "upscaling"
                ]
        )
        #expect(
            panel.renderTargetsSection.statsLabelIdentifier == "RenderTargetsStatsLabel"
        )
    }

    @Test
    func theRenderTargetReadoutShowsTheProviderMemory() throws {
        let providers = FakeWorldProviders()
        providers.renderPerformanceSnapshot = RenderPerformanceSnapshot(
            renderTargets: RenderTargetMemory(entries: [
                RenderTargetEntry(name: "Shadow maps", bytes: 1_048_576, isMemoryless: false),
                RenderTargetEntry(name: "Scene depth", bytes: 0, isMemoryless: true)
            ])
        )
        let panel = try makePanel(providers)
        panel.renderTargetsSection.refreshReadout()
        #expect(panel.renderTargetsSection.statsReadout.contains("Scene depth: memoryless"))
        #expect(panel.renderTargetsSection.statsReadout.hasPrefix("Render targets: 1.0 MB"))

        providers.renderPerformanceSnapshot = nil
        panel.renderTargetsSection.refreshReadout()
        #expect(panel.renderTargetsSection.statsReadout == "Render targets: unavailable")
    }
}

@MainActor
struct PipelineCacheSectionTests {
    @Test
    func theSwitchAndClearReachTheProvider() {
        let providers = FakeWorldProviders()
        let section = PipelineCacheSection()
        section.provider = providers
        section.loadViewIfNeeded()
        #expect(section.enabledControl.accessibilityIdentifier() == "PipelineCacheEnabledControl")
        #expect(section.clearControl.accessibilityIdentifier() == "PipelineCacheClearControl")

        section.enabledControl.state = .off
        section.enabledControl.sendAction(section.enabledControl.action, to: section)
        #expect(!providers.pipelineCacheEnabled)
        #expect(PipelineCacheSection.isOverridden(provider: providers))
        PipelineCacheSection.resetToDefaults(provider: providers)
        #expect(providers.pipelineCacheEnabled)

        section.clearControl.sendAction(section.clearControl.action, to: section)
        #expect(providers.pipelineCacheClears == 1)
        #expect(section.statsReadout.contains("Cleared: 1 files"))
    }

    @Test
    func theReadoutShowsHitsAndMisses() {
        let providers = FakeWorldProviders()
        var stats = PipelineCacheStats()
        stats.archive = .loaded
        stats.hits = 40
        providers.renderPerformanceSnapshot = RenderPerformanceSnapshot(pipelineCache: stats)
        let section = PipelineCacheSection()
        section.provider = providers
        section.loadViewIfNeeded()
        section.refreshReadout()
        #expect(section.statsReadout == "Archive: loaded\nLoaded: 40  Compiled: 0")
    }
}

@MainActor
struct GPUCullingSectionTests {
    @Test
    func theSwitchReachesTheProviderAndCountsAsAnOverride() {
        let providers = FakeWorldProviders()
        let section = GPUCullingSection()
        section.provider = providers
        section.loadViewIfNeeded()
        #expect(section.enabledControl.accessibilityIdentifier() == "GPUCullingEnabledControl")
        #expect(section.enabledControl.state == .on)
        #expect(!GPUCullingSection.isOverridden(provider: providers))

        section.enabledControl.state = .off
        section.enabledControl.sendAction(section.enabledControl.action, to: section)
        #expect(!providers.gpuCullingEnabled)
        #expect(GPUCullingSection.isOverridden(provider: providers))
        GPUCullingSection.resetToDefaults(provider: providers)
        #expect(providers.gpuCullingEnabled)
    }

    @Test
    func theReadoutShowsBothPaths() {
        let providers = FakeWorldProviders()
        providers.renderPerformanceSnapshot = RenderPerformanceSnapshot(
            cpuCulling: CullCounts(cameraVisible: 1, cameraCulled: 2),
            gpuCulling: CullCounts(
                cameraVisible: 30, cameraCulled: 40, shadowVisible: 50, shadowCulled: 60
            )
        )
        let section = GPUCullingSection()
        section.provider = providers
        section.loadViewIfNeeded()
        section.refreshReadout()
        #expect(section.statsReadout == """
        Camera CPU: 1 drawn, 2 culled
        Camera GPU: 30 drawn, 40 culled
        Shadows CPU: 0 drawn, 0 culled
        Shadows GPU: 50 drawn, 60 culled
        """)

        providers.renderPerformanceSnapshot = nil
        section.refreshReadout()
        #expect(section.statsReadout == "Culling: unavailable")
    }
}

private enum RenderingPerformancePanelTestError: Error {
    case notAWorldInspector
}

@MainActor
struct TextureStreamingSectionTests {
    @Test
    func theControlsReachTheProviderAndCountAsOverrides() {
        let providers = FakeWorldProviders()
        let section = TextureStreamingSection()
        section.provider = providers
        section.loadViewIfNeeded()
        #expect(
            section.enabledControl.accessibilityIdentifier() == "TextureStreamingEnabledControl"
        )
        #expect(section.budgetControl.accessibilityIdentifier() == "TextureBudgetControl")
        #expect(section.enabledControl.state == .on)
        #expect(section.budgetControl.titleOfSelectedItem == "Budget 512 MiB")
        #expect(!TextureStreamingSection.isOverridden(provider: providers))

        section.enabledControl.state = .off
        section.enabledControl.sendAction(section.enabledControl.action, to: section)
        section.budgetControl.selectItem(at: 0)
        section.budgetControl.sendAction(section.budgetControl.action, to: section)
        #expect(!providers.textureStreamingEnabled)
        #expect(providers.textureBudgetIndex == 0)
        #expect(TextureStreamingSection.isOverridden(provider: providers))
        TextureStreamingSection.resetToDefaults(provider: providers)
        #expect(providers.textureStreamingEnabled)
        #expect(providers.textureBudgetIndex == 2)
    }

    @Test
    func theReadoutShowsTheMemory() {
        let providers = FakeWorldProviders()
        var snapshot = RenderPerformanceSnapshot()
        snapshot.textureStreaming.streamedTextures = 3
        snapshot.textureStreaming.usedBytes = 2 << 20
        snapshot.textureStreaming.budgetBytes = 512 << 20
        snapshot.textureStreaming.reservedBytes = 16 << 20
        snapshot.textureStreaming.levelsLoaded = 4
        providers.renderPerformanceSnapshot = snapshot
        let section = TextureStreamingSection()
        section.provider = providers
        section.loadViewIfNeeded()
        section.refreshReadout()
        #expect(section.statsReadout == """
        Streamed: 3 textures, 0 reads pending
        Mapped: 2.0 MB of 512.0 MB
        Heaps: 16.0 MB
        Levels: 4 loaded, 0 dropped
        """)
    }
}

@MainActor
struct RayTracedShadowsSectionTests {
    @Test
    func anM1ShowsTheReasonAndDisablesTheSwitch() {
        let providers = FakeWorldProviders()
        var snapshot = RenderPerformanceSnapshot()
        snapshot.rayTracing = .unavailable(reason: RayTracingAvailability.softwareReason)
        providers.renderPerformanceSnapshot = snapshot
        let section = RayTracedShadowsSection()
        section.provider = providers
        section.loadViewIfNeeded()
        section.refreshReadout()
        #expect(
            section.enabledControl.accessibilityIdentifier() == "RayTracedShadowsEnabledControl"
        )
        #expect(section.viewControl.accessibilityIdentifier() == "RayTracedShadowsViewControl")
        #expect(!section.enabledControl.isEnabled)
        #expect(!section.viewControl.isEnabled)
        #expect(section.statsReadout == "Unavailable: " + RayTracingAvailability.softwareReason)
        #expect(!RayTracedShadowsSection.isOverridden(provider: providers))
    }

    @Test
    func anAvailableGPUTakesTheSwitchAndShowsTheStructures() {
        let providers = FakeWorldProviders()
        var snapshot = RenderPerformanceSnapshot()
        snapshot.rayTracing = .available
        snapshot.rayTracedShadows.meshes = 3
        snapshot.rayTracedShadows.instances = 12
        snapshot.rayTracedShadows.bytes = 1 << 20
        providers.renderPerformanceSnapshot = snapshot
        let section = RayTracedShadowsSection()
        section.provider = providers
        section.loadViewIfNeeded()
        section.refreshReadout()
        #expect(section.enabledControl.isEnabled)
        #expect(!section.viewControl.isEnabled)
        section.enabledControl.state = .on
        section.enabledControl.sendAction(section.enabledControl.action, to: section)
        #expect(providers.rayTracedShadowsEnabled)
        #expect(section.viewControl.isEnabled)
        #expect(RayTracedShadowsSection.isOverridden(provider: providers))
        #expect(section.statsReadout == "Meshes: 3  Instances: 12\nStructures: 1.0 MB")
        RayTracedShadowsSection.resetToDefaults(provider: providers)
        #expect(!providers.rayTracedShadowsEnabled)
    }
}
