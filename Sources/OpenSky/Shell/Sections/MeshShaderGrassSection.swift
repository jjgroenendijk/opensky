// Developer > Rendering Performance > Mesh-Shader Grass: switches grass between the classic
// instanced draw and the object and mesh stages, and shows the meshlet counts.

import AppKit
import OpenSkyRendering

final class MeshShaderGrassSection: PanelSectionViewController {
    weak var provider: (any RenderPerformanceControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(
        checkboxWithTitle: "Draw grass with mesh shaders", target: nil, action: nil
    )
    private let statsLabel = PanelComponents.statsLabel(identifier: "MeshShaderGrassStatsLabel")

    override var sectionTitle: String {
        "Mesh-Shader Grass"
    }

    override var sectionIdentifier: String {
        "meshShaderGrass"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any RenderPerformanceControlProviding)?) -> Bool {
        provider?.meshShaderGrassEnabled ?? false
    }

    static func resetToDefaults(provider: (any RenderPerformanceControlProviding)?) {
        provider?.meshShaderGrassEnabled = false
    }

    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.toolTip = "Culls grass meshlets on the GPU. Off draws each blade mesh whole."
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "MeshShaderGrassControl"
        )
        return [enabledControl, statsLabel]
    }

    override func syncControls() {
        let status = provider?.renderPerformanceSnapshot?.meshShaderGrass
        let supported = status != nil && status?.unavailableReason == nil
        enabledControl.isEnabled = supported
        enabledControl.state = supported && provider?.meshShaderGrassEnabled == true ? .on : .off
    }

    override func refreshReadout() {
        guard let snapshot = provider?.renderPerformanceSnapshot else {
            statsLabel.stringValue = "Grass path: unavailable"
            return
        }
        statsLabel.stringValue = RenderPerformanceReadout.meshShaderGrassText(
            snapshot.meshShaderGrass
        )
    }

    @objc private func enabledChanged() {
        provider?.meshShaderGrassEnabled = enabledControl.state == .on
        finishInteraction()
    }
}
