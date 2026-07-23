// World > UI Lab destination panel (M8.1.1): the sidebar verification surface
// for the screen-space UI layer. Toggles the overlay, swaps the built-in sample
// scene, picks a scale preset, and shows a live 2 Hz readout of the last-frame
// UIDrawStats. Built on the shared panel framework (opensky/Shell) as a
// direct-content panel (no sub-sections). Talks to the renderer only through the
// narrow UILabControlProviding seam.

import AppKit

final class UILabPanelViewController: InspectorPanelViewController {
    /// Discrete scale presets surfaced by the popup (points -> pixels factor).
    private static let scalePresets: [(title: String, value: Float)] = [
        ("50%", 0.5), ("100%", 1), ("150%", 1.5), ("200%", 2)
    ]

    /// Live renderer bridge. Weak: the game controller owns this panel's parent
    /// and the renderer, so the panel must not retain back into that graph.
    weak var provider: (any UILabControlProviding)? {
        didSet {
            refocusAction = { [weak provider] in provider?.refocusGameView() }
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let overlayEnabledControl = NSButton(
        checkboxWithTitle: "Enabled", target: nil, action: nil
    )
    let sampleControl = NSButton(
        checkboxWithTitle: "Show sample overlay", target: nil, action: nil
    )
    let scaleControl = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statsLabel = PanelComponents.statsLabel(identifier: "UIStatsLabel")

    /// Current readout text; the verification-surface tests read it directly.
    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        overlayEnabledControl.target = self
        overlayEnabledControl.action = #selector(overlayEnabledChanged)
        overlayEnabledControl.setAccessibilityIdentifier("UIOverlayEnabledControl")

        sampleControl.target = self
        sampleControl.action = #selector(sampleChanged)
        sampleControl.setAccessibilityIdentifier("UILabSampleControl")

        for preset in Self.scalePresets {
            scaleControl.addItem(withTitle: preset.title)
        }
        scaleControl.target = self
        scaleControl.action = #selector(scaleChanged)
        scaleControl.setAccessibilityIdentifier("UIScaleControl")

        return [
            PanelComponents.caption("Screen-space overlay"),
            overlayEnabledControl,
            sampleControl,
            PanelComponents.caption("Scale"),
            scaleControl,
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        overlayEnabledControl.isEnabled = available
        sampleControl.isEnabled = available
        scaleControl.isEnabled = available
        overlayEnabledControl.state = provider?.uiOverlayEnabled == true ? .on : .off
        sampleControl.state = provider?.uiSampleShown == true ? .on : .off
        let scale = provider?.uiScale ?? 1
        if let index = Self.scalePresets.firstIndex(where: { $0.value == scale }) {
            scaleControl.selectItem(at: index)
        }
    }

    override func refreshReadout() {
        guard let snapshot = provider?.uiSnapshot else {
            statsLabel.stringValue = "UI stats unavailable."
            return
        }
        let stats = snapshot.stats
        let state = snapshot.overlayEnabled ? "on" : "off"
        statsLabel.stringValue = """
        Overlay: \(state) · scale \(String(format: "%.2f", snapshot.scale))
        Draw calls: \(stats.drawCalls)
        Quads: \(stats.quads)  Glyphs: \(stats.glyphs)
        Dropped: \(stats.dropped)
        Atlas: \(stats.atlasWidth)x\(stats.atlasHeight)
        """
    }

    /// Test hook: refresh the readout without the ticker running.
    func refreshStats() {
        refreshReadout()
    }

    @objc private func overlayEnabledChanged() {
        provider?.uiOverlayEnabled = overlayEnabledControl.state == .on
        finishInteraction()
    }

    @objc private func sampleChanged() {
        provider?.uiSampleShown = sampleControl.state == .on
        finishInteraction()
    }

    @objc private func scaleChanged() {
        let index = scaleControl.indexOfSelectedItem
        guard Self.scalePresets.indices.contains(index) else { return }
        provider?.uiScale = Self.scalePresets[index].value
        finishInteraction()
    }
}
