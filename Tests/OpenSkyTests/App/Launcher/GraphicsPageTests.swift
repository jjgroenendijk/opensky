// The launcher's Graphics page: its pinned ids, its defaults, and that each switch saves
// the setting the game reads when it starts.

import AppKit
@testable import OpenSky
import OpenSkyGameData
import Testing

@MainActor
struct GraphicsPageTests {
    private func makePage(store: PlayerSettingsStore = PlayerSettingsStore(persistence: nil))
        -> GraphicsPageViewController
    {
        let page = GraphicsPageViewController(reloadStore: { store })
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
        #expect(page.statusLabel.accessibilityIdentifier() == "GraphicsStatsLabel")
    }

    @Test func bothFeaturesStartOn() {
        let page = makePage()
        #expect(page.pipelineCacheControl.state == .on)
        #expect(page.gpuCullingControl.state == .on)
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
    }

    @Test func showingThePageReadsTheSettingsAgain() {
        let store = PlayerSettingsStore(persistence: nil)
        let page = makePage(store: store)
        store.set(.gpuCulling, to: 0)
        page.viewWillAppear()
        #expect(page.gpuCullingControl.state == .off)
    }
}
