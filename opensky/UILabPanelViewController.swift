// World > UI Lab controls panel (M8.1.1): the sidebar verification surface for
// the screen-space UI layer. Toggles the overlay on/off, swaps the built-in
// sample scene in/out, picks a scale preset, and shows a live 2 Hz readout of
// the last-frame UIDrawStats. Talks to the renderer only through the narrow
// UILabControlProviding seam. M8.1.4 extends this panel; kept lean but real.

import AppKit

final class UILabPanelViewController: NSViewController {
    /// Discrete scale presets surfaced by the popup (points -> pixels factor).
    private static let scalePresets: [(title: String, value: Float)] = [
        ("50%", 0.5), ("100%", 1), ("150%", 1.5), ("200%", 2)
    ]

    /// Live renderer bridge. Weak: the game controller owns this panel's parent
    /// and the renderer, so the panel must not retain back into that graph.
    weak var provider: (any UILabControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshStats()
        }
    }

    let overlayEnabledControl = NSButton(
        checkboxWithTitle: "Enabled", target: nil, action: nil
    )
    let sampleControl = NSButton(
        checkboxWithTitle: "Show sample overlay", target: nil, action: nil
    )
    let scaleControl = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statsLabel = NSTextField(wrappingLabelWithString: "")
    private var statsTimer: Timer?

    /// Current readout text; the verification-surface tests read it directly.
    var statsReadout: String {
        statsLabel.stringValue
    }

    override func loadView() {
        let root = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 700))
        root.hasVerticalScroller = true
        root.autohidesScrollers = true
        root.drawsBackground = false

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

        statsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.setAccessibilityIdentifier("UIStatsLabel")
        statsLabel.widthAnchor.constraint(equalToConstant: 272).isActive = true

        let controls: [NSView] = [
            Self.heading("UI Lab"),
            Self.caption("Screen-space overlay"),
            overlayEnabledControl,
            sampleControl,
            Self.caption("Scale"),
            scaleControl,
            statsLabel
        ]
        let stack = NSStackView(views: controls)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        for control in controls {
            control.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        let controlsHeight = controls.reduce(0) { $0 + $1.fittingSize.height }
        let spacingHeight = stack.spacing * CGFloat(max(controls.count - 1, 0))
        let contentHeight = controlsHeight + spacingHeight
            + stack.edgeInsets.top + stack.edgeInsets.bottom
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: contentHeight)
        stack.autoresizingMask = [.width]
        root.documentView = stack
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        syncControls()
        refreshStats()
    }

    /// Begins the live stats readout at 2 Hz. Idempotent; added to the common
    /// run-loop mode so the readout keeps ticking during menu/resize tracking.
    func startInspecting() {
        syncControls()
        refreshStats()
        guard statsTimer == nil else { return }
        let timer = Timer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(statsTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
    }

    /// Stops the readout — called when the panel hides or World leaves screen.
    func stopInspecting() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    private func syncControls() {
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

    @objc private func statsTick() {
        refreshStats()
    }

    func refreshStats() {
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

    private func finishInteraction() {
        refreshStats()
        // Popup/checkbox interaction grabbed first responder; hand it back so
        // the game view keeps receiving WASD/look without a manual click.
        provider?.refocusGameView()
    }

    private static func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 15)
        return label
    }

    private static func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        return label
    }
}
