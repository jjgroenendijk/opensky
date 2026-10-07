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
                == ["renderTargets", "pipelineCache", "gpuCulling"]
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
