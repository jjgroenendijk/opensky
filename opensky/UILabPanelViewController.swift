// Developer > UI Lab destination panel: the sidebar verification surface for the
// UI shell foundation (M8.1). Toggles the screen-space overlay, swaps the
// built-in sample scenes (M8.1.1 lab sample, M8.1.4 localized-strings sample),
// picks a scale preset, previews menu mode (push/pop/clear on the real
// MenuModeController), and shows live 2 Hz readouts of the last-frame
// UIDrawStats, the menu stack, and the translation-provider counts. M8.2.5
// adds the hosted SWFMovieSection: pick a vanilla movie, toggle the SWF layer,
// read its tag/draw stats. M8.3.3 adds the hosted SWFRuntimeSection beside it:
// run that movie's ActionScript, drive it with keys and pointer events, and
// read its movie state, invoke log, and op tally. Built on the shared panel
// framework (opensky/Shell)
// as a direct-content panel. Talks to the engine only through the narrow
// UILabControlProviding and SWFLabControlProviding seams.

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

    /// SWF movie selector (M8.2.5). A self-contained child section hosted by
    /// this direct-content panel, so the SWF controls carry their own sync,
    /// readout, and ticker (docs/tools/app-ui.md "Hosting a section").
    let swfSection = SWFMovieSection()

    /// AS2 runtime driver (M8.3.3). A sibling section rather than more controls
    /// in the selector: it has its own readout cadence and its own three
    /// readouts (movie state, invoke log, op tally).
    let swfRuntimeSection = SWFRuntimeSection()

    weak var swfProvider: (any SWFLabControlProviding)? {
        didSet {
            swfSection.provider = swfProvider
            swfRuntimeSection.provider = swfProvider
        }
    }

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
            stringsStatsLabel,
            host(swfSection),
            host(swfRuntimeSection)
        ]
    }

    /// Adopts a section as a child and wraps it in the standard collapsible
    /// header, matching how a sectioned panel presents its groups. The refocus
    /// indirection reads the panel's current action at call time.
    private func host(_ section: PanelSectionViewController) -> NSView {
        addChild(section)
        section.refocusAction = { [weak self] in self?.refocusAction?() }
        return CollapsibleSectionView(
            title: section.sectionTitle,
            identifier: section.sectionIdentifier,
            content: section.view
        )
    }

    override func startInspecting() {
        super.startInspecting()
        swfSection.startInspecting()
        swfRuntimeSection.startInspecting()
    }

    override func stopInspecting() {
        super.stopInspecting()
        swfSection.stopInspecting()
        swfRuntimeSection.stopInspecting()
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
        PanelComponents.configurePopUp(
            scaleControl, target: self, action: #selector(scaleChanged),
            identifier: "UIScaleControl"
        )
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

/// Readout formatting, split out of the class body so the panel stays inside
/// the strict-lint type-body limit as its hosted sections grow.
extension UILabPanelViewController {
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
}
