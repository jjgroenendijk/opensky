// Developer > Rendering Performance > Pipeline Cache: the switch for the saved
// pipeline archive, a clear button, and how many pipelines this launch loaded from
// the archive or compiled.

import AppKit
import OpenSkyRendering

final class PipelineCacheSection: PanelSectionViewController {
    weak var provider: (any RenderPerformanceControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(
        checkboxWithTitle: "Cache GPU pipelines",
        target: nil,
        action: nil
    )
    let clearControl = NSButton(title: "Clear", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "PipelineCacheStatsLabel")
    /// The last clear's result, until the next launch shows the new archive state.
    private var clearedCount: Int?

    override var sectionTitle: String {
        "Pipeline Cache"
    }

    override var sectionIdentifier: String {
        "pipelineCache"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any RenderPerformanceControlProviding)?) -> Bool {
        provider?.pipelineCacheEnabled == false
    }

    static func resetToDefaults(provider: (any RenderPerformanceControlProviding)?) {
        provider?.pipelineCacheEnabled = true
    }

    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.toolTip = "Loads pipelines an earlier launch saved. Applies on relaunch."
        clearControl.toolTip = "Deletes the saved pipelines; the next launch compiles them again."
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "PipelineCacheEnabledControl"
        )
        PanelComponents.configureButton(
            clearControl, target: self, action: #selector(clearPressed),
            identifier: "PipelineCacheClearControl"
        )
        return [enabledControl, PanelComponents.buttonRow([clearControl]), statsLabel]
    }

    override func syncControls() {
        enabledControl.isEnabled = provider != nil
        clearControl.isEnabled = provider != nil
        enabledControl.state = provider?.pipelineCacheEnabled == false ? .off : .on
    }

    override func refreshReadout() {
        guard let snapshot = provider?.renderPerformanceSnapshot else {
            statsLabel.stringValue = "Pipeline cache: unavailable"
            return
        }
        var text = RenderPerformanceReadout.pipelineCacheText(snapshot.pipelineCache)
        if let clearedCount {
            text += "\nCleared: \(clearedCount) files"
        }
        statsLabel.stringValue = text
    }

    @objc private func enabledChanged() {
        provider?.pipelineCacheEnabled = enabledControl.state == .on
        finishInteraction()
    }

    @objc private func clearPressed() {
        clearedCount = provider?.clearPipelineCache()
        refreshReadout()
        finishInteraction()
    }
}
