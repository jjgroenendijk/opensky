// World > UI Lab destination panel: the sidebar verification surface for the
// UI shell foundation (M8.1). Toggles the screen-space overlay, swaps the
// built-in sample scenes (M8.1.1 lab sample, M8.1.4 localized-strings sample),
// picks a scale preset, previews menu mode (push/pop/clear on the real
// MenuModeController), and shows live 2 Hz readouts of the last-frame
// UIDrawStats, the menu stack, and the translation-provider counts. Built on
// the shared panel framework (opensky/Shell) as a direct-content panel. Talks
// to the engine only through the narrow UILabControlProviding seam.

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

    let menuPushControl = NSButton(title: "Push menu", target: nil, action: nil)
    let menuPopControl = NSButton(title: "Pop", target: nil, action: nil)
    let menuClearControl = NSButton(title: "Clear", target: nil, action: nil)
    private let menuStatsLabel = PanelComponents.statsLabel(identifier: "UIMenuStatsLabel")

    let localizedSampleControl = NSButton(
        checkboxWithTitle: "Show localized sample", target: nil, action: nil
    )
    private let stringsStatsLabel = PanelComponents.statsLabel(identifier: "UIStringsStatsLabel")

    /// Current readout texts; the verification-surface tests read them directly.
    var statsReadout: String {
        statsLabel.stringValue
    }

    var menuReadout: String {
        menuStatsLabel.stringValue
    }

    var stringsReadout: String {
        stringsStatsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.caption("Screen-space overlay"),
            overlayEnabledControl,
            sampleControl,
            localizedSampleControl,
            PanelComponents.caption("Scale"),
            scaleControl,
            statsLabel,
            PanelComponents.caption("Menu mode"),
            PanelComponents.note(
                "Opening a menu pauses world sim; the frame keeps rendering."
            ),
            PanelComponents.buttonRow([menuPushControl, menuPopControl, menuClearControl]),
            menuStatsLabel,
            PanelComponents.caption("Localized strings"),
            stringsStatsLabel
        ]
    }

    private func configureControls() {
        configure(
            overlayEnabledControl, #selector(overlayEnabledChanged), "UIOverlayEnabledControl"
        )
        configure(sampleControl, #selector(sampleChanged), "UILabSampleControl")
        configure(
            localizedSampleControl, #selector(localizedSampleChanged), "UIStringsSampleControl"
        )
        configure(menuPushControl, #selector(menuPushPressed), "UIMenuPushControl")
        configure(menuPopControl, #selector(menuPopPressed), "UIMenuPopControl")
        configure(menuClearControl, #selector(menuClearPressed), "UIMenuClearControl")
        for preset in Self.scalePresets {
            scaleControl.addItem(withTitle: preset.title)
        }
        scaleControl.target = self
        scaleControl.action = #selector(scaleChanged)
        scaleControl.setAccessibilityIdentifier("UIScaleControl")
    }

    private func configure(_ button: NSButton, _ action: Selector, _ identifier: String) {
        button.target = self
        button.action = action
        button.setAccessibilityIdentifier(identifier)
    }

    override func syncControls() {
        let available = provider != nil
        for control: NSControl in [
            overlayEnabledControl, sampleControl, localizedSampleControl, scaleControl,
            menuPushControl, menuPopControl, menuClearControl
        ] {
            control.isEnabled = available
        }
        overlayEnabledControl.state = provider?.uiOverlayEnabled == true ? .on : .off
        sampleControl.state = provider?.uiSampleShown == true ? .on : .off
        localizedSampleControl.state = provider?.uiLocalizedSampleShown == true ? .on : .off
        let scale = provider?.uiScale ?? 1
        if let index = Self.scalePresets.firstIndex(where: { $0.value == scale }) {
            scaleControl.selectItem(at: index)
        }
    }

    override func refreshReadout() {
        refreshUIStats()
        refreshMenuStats()
        refreshStringsStats()
    }

    private func refreshUIStats() {
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

    private func refreshMenuStats() {
        guard let snapshot = provider?.menuModeSnapshot else {
            menuStatsLabel.stringValue = "Menu state unavailable."
            return
        }
        menuStatsLabel.stringValue = """
        Menu mode: \(snapshot.isMenuMode ? "on" : "off")  Depth: \(snapshot.stackDepth)
        Top: \(snapshot.topMenuName ?? "none")
        World sim: \(snapshot.isWorldSimPaused ? "paused" : "running")
        """
    }

    private func refreshStringsStats() {
        guard let snapshot = provider?.localizedLabelsSnapshot else {
            stringsStatsLabel.stringValue = "Strings state unavailable."
            return
        }
        let sample = snapshot.sampleShown ? "on" : "off"
        let install = snapshot.installLoaded
            ? "\(snapshot.installFileCount) files · \(snapshot.installKeyCount) keys"
            : "no game data"
        stringsStatsLabel.stringValue = """
        Sample: \(sample) · \(snapshot.sampleKeyCount) sample keys (\(snapshot.language))
        Install: \(install)
        """
    }

    /// Test hook: refresh the readouts without the ticker running.
    func refreshStats() {
        refreshReadout()
    }

    @objc private func overlayEnabledChanged() {
        provider?.uiOverlayEnabled = overlayEnabledControl.state == .on
        finishInteraction()
    }

    @objc private func sampleChanged() {
        provider?.uiSampleShown = sampleControl.state == .on
        // The two samples share the renderer scene slot; resync so enabling one
        // visibly clears the other checkbox.
        syncControls()
        finishInteraction()
    }

    @objc private func localizedSampleChanged() {
        provider?.uiLocalizedSampleShown = localizedSampleControl.state == .on
        syncControls()
        finishInteraction()
    }

    @objc private func scaleChanged() {
        let index = scaleControl.indexOfSelectedItem
        guard Self.scalePresets.indices.contains(index) else { return }
        provider?.uiScale = Self.scalePresets[index].value
        finishInteraction()
    }

    @objc private func menuPushPressed() {
        provider?.pushPreviewMenu()
        finishInteraction()
    }

    @objc private func menuPopPressed() {
        provider?.popPreviewMenu()
        finishInteraction()
    }

    @objc private func menuClearPressed() {
        provider?.clearPreviewMenus()
        finishInteraction()
    }
}
