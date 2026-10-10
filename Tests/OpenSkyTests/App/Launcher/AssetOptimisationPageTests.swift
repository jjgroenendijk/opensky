// The launcher's Asset Optimisation page: its pinned ids and what it shows before a check.

import AppKit
import Foundation
@testable import OpenSky
import OpenSkyAssetCache
import OpenSkyGameData
import OpenSkyWorld
import Testing

@MainActor
struct AssetOptimisationPageTests {
    private struct NoInstall: Error {}

    private func makePage() -> AssetOptimisationPageViewController {
        AssetOptimisationPageViewController(coordinator: AssetCacheCoordinator(
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
            "AssetOptimisationStatusStatsLabel", "AssetOptimisationStatusDetailStatsLabel",
            "AssetOptimisationConvertControl", "AssetOptimisationCancelControl",
            "AssetOptimisationConvertReasonStatsLabel", "AssetOptimisationProgressIndicator",
            "AssetOptimisationSpaceStatsLabel", "AssetOptimisationEnabledControl",
            "AssetOptimisationTextureQualityControl", "AssetOptimisationTextureQualityStatsLabel",
            "AssetOptimisationQualityLimitsStatsLabel",
            "AssetOptimisationTextureFormatColourControl",
            "AssetOptimisationTextureFormatNormalControl",
            "AssetOptimisationTextureFormatDataControl",
            "AssetOptimisationDirectLoadControl", "AssetOptimisationDirectLoadTexturesControl",
            "AssetOptimisationDirectLoadMeshesControl",
            "AssetOptimisationDirectLoadAllDisksControl",
            "AssetOptimisationDirectLoadStatsLabel", "AssetOptimisationFolderStatsLabel",
            "AssetOptimisationSizeStatsLabel", "AssetOptimisationChooseFolderControl",
            "AssetOptimisationResetFolderControl", "AssetOptimisationClearControl",
            "AssetOptimisationShowDetailsControl"
        ] {
            #expect(find(identifier, in: page.view) != nil, "\(identifier)")
        }
    }

    @Test func beforeACheckConvertWaitsAndSaysWhy() {
        let page = makePage()
        page.loadViewIfNeeded()
        #expect(page.qualityPopUp.itemTitles.count == TextureQuality.allCases.count)
        #expect(page.qualityPopUp.indexOfSelectedItem == Int(TextureQuality.default.rawValue))
        #expect(!page.convertButton.isEnabled)
        #expect(page.convertReasonLabel.stringValue == "Wait for the check to finish")
        #expect(!page.cancelButton.isEnabled)
        #expect(page.sizeLabel.stringValue == "Size: empty")
    }

    @Test func choosingATextureQualitySavesIt() {
        let page = makePage()
        page.loadViewIfNeeded()
        page.qualityPopUp.selectItem(at: Int(TextureQuality.low.rawValue))
        page.qualityPopUp.sendAction(page.qualityPopUp.action, to: page.qualityPopUp.target)
        #expect(page.coordinator.settings.textureOutput.quality == .low)
    }

    @Test func aFormatChoiceSavesItForItsGroup() {
        let page = makePage()
        page.loadViewIfNeeded()
        let normal = page.formatPopUps[AssetTextureClass.allCases.firstIndex(of: .normal) ?? 0]
        normal.selectItem(at: Int(TextureFormatChoice.astc6x6.rawValue))
        normal.sendAction(normal.action, to: normal.target)
        #expect(page.coordinator.settings.textureOutput.formats == [.normal: .astc6x6])
    }

    @Test func directMeshLoadingStartsOffAndSaves() {
        let page = makePage()
        page.loadViewIfNeeded()
        #expect(page.directLoadCheckbox.state == .on)
        #expect(page.directMeshesCheckbox.state == .off)
        page.directMeshesCheckbox.performClick(nil)
        #expect(page.coordinator.settings.directLoad.meshes)
        #expect(page.coordinator.settings.directLoad.textures)
        page.directLoadCheckbox.performClick(nil)
        #expect(!page.directTexturesCheckbox.isEnabled)
        #expect(page.directLoadLabel.stringValue == "Off: optimised files load through the CPU")
    }
}
