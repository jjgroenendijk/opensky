// Developer > Rendering Performance > Texture Streaming: the switch, the memory budget,
// and how much texture memory the streamed levels use.

import AppKit
import OpenSkyGameData
import OpenSkyRendering

final class TextureStreamingSection: PanelSectionViewController {
    static let defaultBudgetIndex = 0

    weak var provider: (any RenderPerformanceControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(checkboxWithTitle: "Stream textures", target: nil, action: nil)
    let budgetControl = NSPopUpButton()
    private let statsLabel = PanelComponents.statsLabel(identifier: "TextureStreamingStatsLabel")

    override var sectionTitle: String {
        "Texture Streaming"
    }

    override var sectionIdentifier: String {
        "textureStreaming"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any RenderPerformanceControlProviding)?) -> Bool {
        guard let provider else { return false }
        return !provider.textureStreamingEnabled || provider
            .textureBudgetIndex != defaultBudgetIndex
    }

    static func resetToDefaults(provider: (any RenderPerformanceControlProviding)?) {
        provider?.textureStreamingEnabled = true
        provider?.textureBudgetIndex = defaultBudgetIndex
    }

    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.toolTip = "Large textures keep only the mip levels the camera needs."
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "TextureStreamingEnabledControl"
        )
        budgetControl.addItems(
            withTitles: TextureBudget.choiceTitles.map { "Budget: \($0)" }
        )
        budgetControl.toolTip = "Far textures drop detail when the levels pass this size."
        PanelComponents.configurePopUp(
            budgetControl, target: self, action: #selector(budgetChanged),
            identifier: "TextureBudgetControl"
        )
        return [enabledControl, budgetControl, statsLabel]
    }

    override func syncControls() {
        enabledControl.isEnabled = provider != nil
        budgetControl.isEnabled = provider != nil
        enabledControl.state = provider?.textureStreamingEnabled == true ? .on : .off
        budgetControl.selectItem(at: provider?.textureBudgetIndex ?? Self.defaultBudgetIndex)
    }

    override func refreshReadout() {
        guard let snapshot = provider?.renderPerformanceSnapshot else {
            statsLabel.stringValue = "Streaming: unavailable"
            return
        }
        statsLabel.stringValue = RenderPerformanceReadout.textureStreamingText(
            snapshot.textureStreaming
        )
    }

    @objc private func enabledChanged() {
        provider?.textureStreamingEnabled = enabledControl.state == .on
        finishInteraction()
    }

    @objc private func budgetChanged() {
        provider?.textureBudgetIndex = max(budgetControl.indexOfSelectedItem, 0)
        finishInteraction()
    }
}
