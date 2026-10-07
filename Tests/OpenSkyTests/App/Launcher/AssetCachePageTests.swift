// The launcher's Asset Cache page: its pinned ids and what it shows before a check.

import AppKit
import Foundation
@testable import OpenSky
import OpenSkyAssetCache
import OpenSkyGameData
import OpenSkyWorld
import Testing

@MainActor
struct AssetCachePageTests {
    private struct NoInstall: Error {}

    private func makePage() -> AssetCachePageViewController {
        AssetCachePageViewController(coordinator: AssetCacheCoordinator(
            store: PlayerSettingsStore(persistence: nil),
            environment: AssetCacheCoordinator.Environment(
                locate: { throw NoInstall() }, makeConverters: { _ in [] }
            )
        ))
    }

    private func find(_ identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier {
            return view
        }
        return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
    }

    @Test func idsArePinned() {
        let page = makePage()
        page.loadViewIfNeeded()
        for identifier in [
            "AssetCacheEnabledControl", "AssetCachePresetControl", "AssetCachePresetStatsLabel",
            "AssetCacheFolderStatsLabel", "AssetCacheChooseFolderControl",
            "AssetCacheResetFolderControl",
            "AssetCacheLimitControl", "AssetCacheSizeStatsLabel", "AssetCacheStateStatsLabel",
            "AssetCacheBuildStatsLabel", "AssetCacheBuildProgressIndicator",
            "AssetCacheBuildControl",
            "AssetCacheCancelControl", "AssetCacheCheckControl", "AssetCacheClearControl",
            "AssetCacheKindTexturesControl", "AssetCacheKindMeshesControl",
            "AssetCacheKindCollisionControl", "AssetCacheRetiredKindsStatsLabel",
            "AssetCacheLaunchFastLoadControl", "AssetCacheLaunchFastMeshLoadControl"
        ] {
            #expect(find(identifier, in: page.view) != nil, "\(identifier)")
        }
    }

    @Test func thePageShowsThePresetsAndNoBuildYet() {
        let page = makePage()
        page.loadViewIfNeeded()
        #expect(page.presetPopUp.itemTitles.count == AssetQualityPreset.allCases.count)
        #expect(page.presetPopUp.indexOfSelectedItem == Int(AssetQualityPreset.default.rawValue))
        #expect(page.stateLabel.stringValue == "State: not checked")
        #expect(page.buildLabel.stringValue == "Build: none")
        #expect(!page.cancelButton.isEnabled)
        #expect(page.buildButton.isEnabled)
    }

    @Test func choosingAPresetSavesIt() {
        let page = makePage()
        page.loadViewIfNeeded()
        page.presetPopUp.selectItem(at: Int(AssetQualityPreset.highestQuality.rawValue))
        page.presetPopUp.sendAction(page.presetPopUp.action, to: page.presetPopUp.target)
        #expect(page.coordinator.settings.preset == .highestQuality)
    }

    @Test func aKindSwitchSavesItAndAudioHasNone() throws {
        let page = makePage()
        page.loadViewIfNeeded()
        #expect(page.kindCheckboxes.count == 3)
        #expect(find("AssetCacheKindAudioControl", in: page.view) == nil)
        let textures = try #require(
            find("AssetCacheKindTexturesControl", in: page.view) as? NSButton
        )
        #expect(textures.state == .on)
        textures.performClick(nil)
        #expect(page.coordinator.settings.kinds == [.mesh, .collision])
    }

    @Test func fastMeshLoadingStartsOffAndSaves() {
        let page = makePage()
        page.loadViewIfNeeded()
        #expect(page.fastLoadCheckbox.state == .on)
        #expect(page.fastMeshLoadCheckbox.state == .off)
        page.fastMeshLoadCheckbox.performClick(nil)
        #expect(page.coordinator.settings.fastMeshLoad)
        #expect(page.coordinator.settings.fastLoad)
    }
}
