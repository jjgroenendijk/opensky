// Developer > Rendering Performance > Upscaling: the render scale MetalFX upscales from,
// and the sizes and history resets of the last frame.

import AppKit
import OpenSkyGameData
import OpenSkyRendering

final class UpscalingSection: PanelSectionViewController {
    weak var provider: (any RenderPerformanceControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let scaleControl = NSPopUpButton()
    let upscalerControl = NSPopUpButton()
    private let statsLabel = PanelComponents.statsLabel(identifier: "UpscalingStatsLabel")

    override var sectionTitle: String {
        "Upscaling"
    }

    override var sectionIdentifier: String {
        "upscaling"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any RenderPerformanceControlProviding)?) -> Bool {
        provider.map { $0.renderScale != .off || $0.upscaler != .temporal } ?? false
    }

    static func resetToDefaults(provider: (any RenderPerformanceControlProviding)?) {
        provider?.renderScale = .off
        provider?.upscaler = .temporal
    }

    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        scaleControl.addItems(withTitles: PlayerSettingsCatalog.renderScaleOptions)
        scaleControl.toolTip = "Renders the scene smaller and lets MetalFX upscale it."
        PanelComponents.configurePopUp(
            scaleControl, target: self, action: #selector(scaleChanged),
            identifier: "RenderScaleControl"
        )
        upscalerControl.addItems(withTitles: PlayerSettingsCatalog.upscalerOptions)
        upscalerControl.toolTip = "Temporal also smooths edges; spatial costs less GPU time."
        PanelComponents.configurePopUp(
            upscalerControl, target: self, action: #selector(upscalerChanged),
            identifier: "UpscalerControl"
        )
        return [PanelComponents.group([scaleControl, upscalerControl]), statsLabel]
    }

    override func syncControls() {
        scaleControl.isEnabled = provider != nil
        scaleControl.selectItem(at: provider?.renderScale.settingIndex ?? 0)
        upscalerControl.isEnabled = provider != nil
        upscalerControl.selectItem(at: provider?.upscaler.rawValue ?? 0)
    }

    override func refreshReadout() {
        guard let provider, let snapshot = provider.renderPerformanceSnapshot else {
            statsLabel.stringValue = "Upscaling: unavailable"
            return
        }
        statsLabel.stringValue = RenderPerformanceReadout.upscalingText(
            scale: provider.renderScale, status: snapshot.upscaling
        )
    }

    @objc private func scaleChanged() {
        provider?.renderScale = RenderScale(settingIndex: scaleControl.indexOfSelectedItem)
        finishInteraction()
    }

    @objc private func upscalerChanged() {
        provider?.upscaler = UpscalerKind(settingIndex: upscalerControl.indexOfSelectedItem)
        finishInteraction()
    }
}
