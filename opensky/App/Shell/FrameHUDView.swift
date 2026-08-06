// Always-on frame readout pinned over the live game view: fps, frame time,
// draw calls, drawn/culled instances, resident cells and process footprint.
//
// This is an AppKit overlay inside the shell's game slot, deliberately not a
// render pass. Two reasons. It needs no shader, pipeline or font-atlas work to
// draw text over the world, and — the load-bearing one — it must stay out of
// `Renderer.renderOffscreen`, which feeds `openskycli screenshot`, the bench
// loop and every offscreen evidence capture. A HUD encoded into the scene pass
// would burn itself into those captures; an overlay view cannot, because the
// offscreen path never touches the view hierarchy.
//
// It reads the same `FrameStatsProviding` / `SceneStatsProviding` snapshots the
// World inspector reads, so the two surfaces can never quote different numbers,
// and it refreshes on the shared 2 Hz `InspectionTicker` rather than a timer of
// its own.

import AppKit

@MainActor
final class FrameHUDView: NSView {
    /// Persisted user preference: is the HUD wanted at all. Default visible.
    static let visibilityDefaultsKey = "frameHUD.visible"

    weak var frameStatsProvider: (any FrameStatsProviding)?
    weak var sceneStatsProvider: (any SceneStatsProviding)?

    private let statsLabel = NSTextField(labelWithString: "")
    private let ticker = InspectionTicker()
    private var isCovered = false
    private var isSuspended = true

    /// True while the refresh timer is scheduled. A hidden HUD must cost
    /// nothing, so this is false whenever the HUD is off or covered.
    var isTicking: Bool {
        ticker.isActive
    }

    /// Current readout text; the verification tests read it directly.
    var statsReadout: String {
        statsLabel.stringValue
    }

    /// The persisted show/hide choice, independent of whether the game view is
    /// currently covered by a full-content destination.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.visibilityDefaultsKey)
            applyVisibility()
        }
    }

    init() {
        isEnabled = Self.loadEnabled()
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 60))
        setUpSubviews()
        applyVisibility()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    // MARK: - Shell hooks

    /// Points the HUD at a (new) live controller; a Settings reload swaps the
    /// whole provider graph underneath it.
    func wire(providers: any WorldControlProviders) {
        frameStatsProvider = providers
        sceneStatsProvider = providers
        refresh()
    }

    /// Mirrors `ShellContentViewController.setGameCovered`: a full-content
    /// destination replaces the world, so its numbers must not float on top.
    func setGameCovered(_ covered: Bool) {
        guard covered != isCovered else { return }
        isCovered = covered
        applyVisibility()
    }

    /// Called when the content area leaves screen: stop polling entirely.
    func suspendUpdates() {
        isSuspended = true
        applyVisibility()
    }

    /// Called when the content area appears: resume polling if the HUD shows.
    func resumeUpdates() {
        isSuspended = false
        applyVisibility()
    }

    // MARK: - Readout

    func refresh() {
        statsLabel.stringValue = Self.statsText(
            frame: frameStatsProvider?.frameStatsSnapshot ?? .empty,
            scene: sceneStatsProvider?.sceneStatsSnapshot ?? .empty
        )
    }

    /// Formats one HUD reading. Before the first stats window closes there is
    /// no measurement at all, and rendering the zeroed snapshot would read as a
    /// stalled renderer; `gpuMS` stays nil until a counter-heap pair resolves.
    nonisolated static func statsText(
        frame: FrameStatsSnapshot,
        scene: SceneStatsSnapshot
    ) -> String {
        let timing: String
        if frame.hasMeasurement {
            let gpu = frame.gpuMS.map { String(format: "%.2f ms", $0) } ?? "n/a"
            timing = String(
                format: "FPS %.0f  Frame %.2f ms  GPU %@",
                frame.fps, frame.frameMS, gpu
            )
        } else {
            timing = "FPS measuring"
        }
        let memory = scene.memoryFootprintMB.map { String(format: "%.0f MB", $0) } ?? "n/a"
        return """
        \(timing)
        Draws \(scene.drawCalls)  Drawn \(scene.drawnInstances)  \
        Culled \(scene.culledInstances)
        Cells \(scene.residentCellCount)  Memory \(memory)
        """
    }

    // MARK: - Visibility

    private func applyVisibility() {
        let shows = isEnabled && !isCovered
        isHidden = !shows
        guard shows, !isSuspended else {
            ticker.stop()
            return
        }
        refresh()
        ticker.start { [weak self] in self?.refresh() }
    }

    private static func loadEnabled() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: visibilityDefaultsKey) != nil else { return true }
        return defaults.bool(forKey: visibilityDefaultsKey)
    }

    // MARK: - Appearance

    private func setUpSubviews() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        // Translucent so the frame underneath stays readable; the palette is
        // the shell's, never a hand-picked color (docs/tools/app-ui.md).
        layer?.backgroundColor = Theme.windowBackground.withAlphaComponent(0.72).cgColor
        layer?.borderColor = Theme.divider.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 4

        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        // Mono-digit so the numbers do not jitter as their widths change.
        statsLabel.font = PanelMetrics.monoDigitFont
        statsLabel.textColor = Theme.parchmentDim
        statsLabel.maximumNumberOfLines = 0
        statsLabel.setAccessibilityIdentifier("FrameHUDStatsLabel")
        addSubview(statsLabel)

        let inset = PanelMetrics.rowSpacing
        NSLayoutConstraint.activate([
            statsLabel.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            statsLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            statsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            statsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset)
        ])
    }
}
