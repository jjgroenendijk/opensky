// World > Environment > Terrain: the normal map toggle and how many maps the
// terrain in the scene has.

import AppKit
import OpenSkyWorld

final class TerrainSection: PanelSectionViewController {
    weak var provider: (any TerrainShadingControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let normalMapsControl = NSButton(
        checkboxWithTitle: "Terrain normal maps", target: nil, action: nil
    )
    private let statsLabel = PanelComponents.statsLabel(identifier: "TerrainStatsLabel")

    override var sectionTitle: String {
        "Terrain"
    }

    override var sectionIdentifier: String {
        "terrain"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any TerrainShadingControlProviding)?) -> Bool {
        provider?.terrainNormalMapsEnabled == false
    }

    static func resetToDefaults(provider: (any TerrainShadingControlProviding)?) {
        provider?.terrainNormalMapsEnabled = true
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            normalMapsControl, target: self, action: #selector(normalMapsChanged),
            identifier: "TerrainNormalMapsControl"
        )
        normalMapsControl.toolTip = "Light the ground with the land textures' normal maps"
        return [normalMapsControl, statsLabel]
    }

    override func syncControls() {
        normalMapsControl.isEnabled = provider != nil
        normalMapsControl.state = provider?.terrainNormalMapsEnabled == true ? .on : .off
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Terrain: unavailable"
            return
        }
        statsLabel.stringValue = """
        Terrain quadrants: \(provider.terrainQuadrantCount)
        Normal maps: \(provider.terrainNormalMapCount)
        """
    }

    @objc private func normalMapsChanged() {
        provider?.terrainNormalMapsEnabled = normalMapsControl.state == .on
        finishInteraction()
    }
}
