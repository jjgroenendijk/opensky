// World > Environment > Surface Shading: one switch per lit-mesh term, and how
// many draws in the scene use each.

import AppKit
import OpenSkyGameData
import OpenSkyWorld

final class SurfaceShadingSection: PanelSectionViewController {
    weak var provider: (any SurfaceShadingControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let controls: [(SurfaceShadingSetting, NSButton)] = SurfaceShadingSetting.allCases.map {
        ($0, NSButton(checkboxWithTitle: $0.title, target: nil, action: nil))
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "SurfaceShadingStatsLabel")

    override var sectionTitle: String {
        "Surface Shading"
    }

    override var sectionIdentifier: String {
        "surfaceShading"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any SurfaceShadingControlProviding)?) -> Bool {
        guard let provider else { return false }
        return SurfaceShadingSetting.allCases.contains { !provider.isShadingEnabled($0) }
    }

    static func resetToDefaults(provider: (any SurfaceShadingControlProviding)?) {
        for setting in SurfaceShadingSetting.allCases {
            provider?.setShading(setting, enabled: true)
        }
    }

    /// `ShadingNormalMapsControl` for `.normalMaps`.
    static func identifier(_ setting: SurfaceShadingSetting) -> String {
        "Shading\(setting.controlName)Control"
    }

    override func makeContentViews() -> [NSView] {
        for (setting, button) in controls {
            PanelComponents.configureCheckbox(
                button, target: self, action: #selector(termChanged(_:)),
                identifier: Self.identifier(setting)
            )
            button.toolTip = setting.toolTip
        }
        return controls.map(\.1) + [statsLabel]
    }

    override func syncControls() {
        for (setting, button) in controls {
            button.isEnabled = provider != nil
            button.state = provider?.isShadingEnabled(setting) == true ? .on : .off
        }
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Surface shading: unavailable"
            return
        }
        let counted: [SurfaceShadingSetting] = [
            .normalMaps, .specular, .glow, .softAndRimLight, .backLight, .faceTint, .tintColor,
            .reflections, .parallax
        ]
        statsLabel.stringValue = counted.map {
            "\($0.title): \(provider.shadingDrawCount($0)) draws"
        }.joined(separator: "\n")
    }

    @objc private func termChanged(_ sender: NSButton) {
        guard let setting = controls.first(where: { $0.1 === sender })?.0 else { return }
        provider?.setShading(setting, enabled: sender.state == .on)
        finishInteraction()
    }
}
