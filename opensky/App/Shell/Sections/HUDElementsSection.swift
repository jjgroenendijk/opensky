// World > HUD & Interaction > Elements: A/B controls over the live vanilla
// HUD layer. Every override feeds the same bridge used by gameplay.

import AppKit

final class HUDElementsSection: PanelSectionViewController {
    nonisolated static let scalePresets: [(title: String, value: Float)] = [
        ("50%", 0.5), ("75%", 0.75), ("100%", 1), ("125%", 1.25),
        ("150%", 1.5), ("200%", 2)
    ]

    weak var provider: (any HUDControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let layerControl = NSButton(checkboxWithTitle: "Draw HUD layer", target: nil, action: nil)
    let crosshairControl = NSButton(checkboxWithTitle: "Crosshair", target: nil, action: nil)
    let metersControl = NSButton(checkboxWithTitle: "Actor meters", target: nil, action: nil)
    let compassControl = NSButton(checkboxWithTitle: "Compass", target: nil, action: nil)
    let markersControl = NSButton(
        checkboxWithTitle: "Interaction marker", target: nil, action: nil
    )
    let promptControl = NSButton(
        checkboxWithTitle: "Activation prompt", target: nil, action: nil
    )
    let placeholderTextControl = NSButton(
        checkboxWithTitle: "Authored placeholder text", target: nil, action: nil
    )
    let scaleControl = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statsLabel = PanelComponents.statsLabel(identifier: "HUDElementsStatsLabel")

    var statsReadout: String {
        statsLabel.stringValue
    }

    override var sectionTitle: String {
        "Elements"
    }

    override var sectionIdentifier: String {
        "hudElements"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any HUDControlProviding)?) -> Bool {
        guard let provider else { return false }
        return !provider.hudLayerEnabled
            || !provider.hudCrosshairEnabled
            || !provider.hudMetersEnabled
            || !provider.hudCompassEnabled
            || !provider.hudMarkersEnabled
            || !provider.hudPromptEnabled
            || provider.hudPlaceholderTextEnabled
            || provider.hudScale != 1
    }

    static func resetToDefaults(provider: (any HUDControlProviding)?) {
        guard let provider else { return }
        provider.hudLayerEnabled = true
        provider.hudCrosshairEnabled = true
        provider.hudMetersEnabled = true
        provider.hudCompassEnabled = true
        provider.hudMarkersEnabled = true
        provider.hudPromptEnabled = true
        provider.hudPlaceholderTextEnabled = false
        provider.hudScale = 1
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.group([
                layerControl, crosshairControl, metersControl, compassControl,
                markersControl, promptControl, placeholderTextControl
            ]),
            PanelComponents.group([
                PanelComponents.caption("Scale"), scaleControl
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        for control: NSControl in [
            layerControl, crosshairControl, compassControl,
            metersControl, markersControl, promptControl,
            placeholderTextControl, scaleControl
        ] {
            control.isEnabled = available
        }
        layerControl.state = provider?.hudLayerEnabled == true ? .on : .off
        crosshairControl.state = provider?.hudCrosshairEnabled == true ? .on : .off
        metersControl.state = provider?.hudMetersEnabled == true ? .on : .off
        compassControl.state = provider?.hudCompassEnabled == true ? .on : .off
        markersControl.state = provider?.hudMarkersEnabled == true ? .on : .off
        promptControl.state = provider?.hudPromptEnabled == true ? .on : .off
        placeholderTextControl.state = provider?.hudPlaceholderTextEnabled == true ? .on : .off
        let scale = provider?.hudScale ?? 1
        let index = Self.scalePresets.firstIndex { $0.value == scale } ?? 2
        scaleControl.selectItem(at: index)
    }

    override func refreshReadout() {
        guard let snapshot = provider?.hudControlSnapshot else {
            statsLabel.stringValue = "HUD: unavailable"
            return
        }
        let state = snapshot.isLoaded ? "loaded" : "disabled"
        let error = snapshot.loadError.map { "\nError: \($0)" } ?? ""
        statsLabel.stringValue = """
        HUD: \(state) · scale \(String(format: "%.2f", snapshot.scale))
        Draw calls: \(snapshot.drawStats.drawCalls) · skipped \(snapshot.drawStats.skippedItems)\
        \(error)
        """
    }

    private func configureControls() {
        configure(layerControl, action: #selector(layerChanged), id: "HUDLayerEnabledControl")
        configure(
            crosshairControl, action: #selector(crosshairChanged), id: "HUDCrosshairControl"
        )
        configure(metersControl, action: #selector(metersChanged), id: "HUDMetersControl")
        configure(compassControl, action: #selector(compassChanged), id: "HUDCompassControl")
        configure(markersControl, action: #selector(markersChanged), id: "HUDMarkersControl")
        configure(promptControl, action: #selector(promptChanged), id: "HUDPromptControl")
        configure(
            placeholderTextControl,
            action: #selector(placeholderTextChanged),
            id: "HUDPlaceholderTextControl"
        )
        for preset in Self.scalePresets {
            scaleControl.addItem(withTitle: preset.title)
        }
        PanelComponents.configurePopUp(
            scaleControl, target: self, action: #selector(scaleChanged),
            identifier: "HUDScaleControl"
        )
    }

    private func configure(_ control: NSButton, action: Selector, id: String) {
        PanelComponents.configureCheckbox(
            control, target: self, action: action, identifier: id
        )
    }

    @objc private func layerChanged() {
        provider?.hudLayerEnabled = layerControl.state == .on
        finishInteraction()
    }

    @objc private func crosshairChanged() {
        provider?.hudCrosshairEnabled = crosshairControl.state == .on
        finishInteraction()
    }

    @objc private func compassChanged() {
        provider?.hudCompassEnabled = compassControl.state == .on
        finishInteraction()
    }

    @objc private func metersChanged() {
        provider?.hudMetersEnabled = metersControl.state == .on
        finishInteraction()
    }

    @objc private func markersChanged() {
        provider?.hudMarkersEnabled = markersControl.state == .on
        finishInteraction()
    }

    @objc private func promptChanged() {
        provider?.hudPromptEnabled = promptControl.state == .on
        finishInteraction()
    }

    @objc private func placeholderTextChanged() {
        provider?.hudPlaceholderTextEnabled = placeholderTextControl.state == .on
        finishInteraction()
    }

    @objc private func scaleChanged() {
        let index = scaleControl.indexOfSelectedItem
        guard Self.scalePresets.indices.contains(index) else { return }
        provider?.hudScale = Self.scalePresets[index].value
        finishInteraction()
    }
}
