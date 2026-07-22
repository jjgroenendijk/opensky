// World > Environment controls panel: the first sidebar verification surface
// (M7.1.2). Hosts the sun-shadow quality selector (Off/Low/High) bound to the
// live renderer, a cheap 2 Hz inspection readout of the per-frame shadow draw
// stats + CPU time, and a note about the `H` dev A/B toggle. Talks to the
// renderer only through ShadowControlProviding so it never touches renderer
// internals. Weather/particles/grass controls join this panel in M7.2-7.5.

import AppKit

/// Renderer-facing surface the Environment panel drives. GameViewController
/// implements it over its live renderer; a nil renderer degrades to defaults
/// so the panel never crashes when Metal 4 is unavailable.
@MainActor
protocol ShadowControlProviding: AnyObject {
    var shadowQuality: ShadowQuality { get set }
    var shadowDrawStats: ShadowDrawStats { get }
    var shadowUpdateMS: Double { get }
    var shadowsActive: Bool { get }
    /// Return keyboard focus to the World view so WASD/look keep working after
    /// a control interaction steals first responder.
    func refocusGameView()
}

@MainActor
protocol TerrainLODControlProviding: AnyObject {
    var terrainLODConfigurationSnapshot: TerrainLODConfigurationSnapshot { get }
    func applyTerrainLODConfiguration(_ configuration: TerrainLODConfiguration) -> Bool
    func resetTerrainLODConfiguration()
}

/// Renderer-facing weather surface the Environment panel drives (M7.2.2):
/// force/inspect the exterior weather runtime without touching CLI or code.
/// A nil renderer / no weather data degrades to an empty list + calm readout.
@MainActor
protocol WeatherControlProviding: AnyObject {
    /// Editor IDs of forceable weathers, sorted; empty when no weather data.
    var selectableWeatherNames: [String] { get }
    /// Force a weather by editor ID (timed transition); nil resumes automatic.
    func forceWeather(named name: String?)
    /// Force the stable data-driven precipitation acceptance presets.
    func forceWeather(_ preset: WeatherPreset)
    /// Editor ID of the weather currently in effect, nil when inactive.
    var currentWeatherName: String? { get }
    /// 0-1 progress of the active transition (1 when settled).
    var weatherTransitionFraction: Float { get }
    /// Freeze/resume only the weather cross-fade.
    var weatherTransitionsPaused: Bool { get set }
    /// Published wind for the readout.
    var windState: WindState { get }
    /// Exterior sky clock in game-hours (0-24). Drives the time-of-day keyframe
    /// blend live and the sun position; persisted across launches by the setter.
    var timeOfDay: Float { get set }
}

nonisolated struct ParticleControlSnapshot: Equatable {
    let systemCount: Int
    let emitterCount: Int
    let liveCount: Int
}

@MainActor
protocol ParticleControlProviding: AnyObject {
    var particlesEnabled: Bool { get set }
    var particlesFrozen: Bool { get set }
    var particleEmissionScale: Float { get set }
    var particleSnapshot: ParticleControlSnapshot { get }
}

@MainActor
protocol PrecipitationControlProviding: AnyObject {
    var precipitationEnabled: Bool { get set }
    var precipitationSnapshot: PrecipitationRuntimeSnapshot { get }
}

final class EnvironmentPanelViewController: NSViewController {
    /// Live renderer bridge. Weak: the game controller owns this panel's parent
    /// and the renderer, so the panel must not retain back into that graph.
    weak var provider: (any ShadowControlProviding & TerrainLODControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncQualitySelection()
            syncLODFields()
            refreshStats()
        }
    }

    /// Live weather bridge (M7.2.2). Same owner + threading as `provider`.
    weak var weatherProvider: (any WeatherControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncWeatherMenu()
            syncTimeOfDay()
            refreshStats()
        }
    }

    weak var particleProvider: (any ParticleControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncParticleControls()
            refreshStats()
        }
    }

    weak var precipitationProvider: (any PrecipitationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncPrecipitationControls()
            refreshStats()
        }
    }

    private let qualityControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let weatherControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let clearWeatherControl = NSButton(title: "Clear", target: nil, action: nil)
    let rainWeatherControl = NSButton(title: "Rain", target: nil, action: nil)
    let snowWeatherControl = NSButton(title: "Snow", target: nil, action: nil)
    let weatherTransitionsPausedControl = NSButton(
        checkboxWithTitle: "Pause transitions", target: nil, action: nil
    )
    let timeControl = NSSlider(
        value: Double(TimeOfDaySettings.fallback),
        minValue: Double(TimeOfDaySettings.range.lowerBound),
        maxValue: Double(TimeOfDaySettings.range.upperBound),
        target: nil,
        action: nil
    )
    let timeLabel = NSTextField(labelWithString: "")
    private let statsLabel = NSTextField(wrappingLabelWithString: "")
    let particlesEnabledControl = NSButton(
        checkboxWithTitle: "Enabled", target: nil, action: nil
    )
    let particlesFrozenControl = NSButton(
        checkboxWithTitle: "Freeze simulation", target: nil, action: nil
    )
    let precipitationEnabledControl = NSButton(
        checkboxWithTitle: "Enabled", target: nil, action: nil
    )
    let emissionControl = NSSlider(
        value: 1, minValue: 0, maxValue: 2, target: nil, action: nil
    )
    let emissionLabel = NSTextField(labelWithString: "")
    private let level0Field = NSTextField()
    private let level1Field = NSTextField()
    private let maximumField = NSTextField()
    private let treeField = NSTextField()
    private let lodStatusLabel = NSTextField(wrappingLabelWithString: "")
    private var statsTimer: Timer?
    private var positionedScrollView = false
    private let qualities = ShadowQuality.allCases

    override func loadView() {
        let root = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 700))
        root.hasVerticalScroller = true
        root.autohidesScrollers = true
        root.drawsBackground = false

        for quality in qualities {
            qualityControl.addItem(withTitle: Self.title(for: quality))
        }
        qualityControl.target = self
        qualityControl.action = #selector(qualityChanged)
        qualityControl.setAccessibilityIdentifier("ShadowQualityControl")

        statsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.setAccessibilityIdentifier("ShadowStatsLabel")
        statsLabel.widthAnchor.constraint(equalToConstant: 272).isActive = true

        let note = NSTextField(
            wrappingLabelWithString:
            "Press H in the World view to toggle shadows on/off (dev A/B)."
        )
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.widthAnchor.constraint(equalToConstant: 272).isActive = true

        let shadowViews: [NSView] = [
            Self.heading("Environment"),
            Self.caption("Sun shadows"),
            qualityControl,
            statsLabel,
            note
        ]
        let controls = shadowViews + makeWeatherViews() + makeParticleViews()
            + makePrecipitationViews() + makeLODViews()
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

    override func viewDidLayout() {
        super.viewDidLayout()
        guard
            !positionedScrollView,
            let scrollView = view as? NSScrollView,
            let document = scrollView.documentView
        else { return }
        let top = max(document.frame.height - scrollView.contentView.bounds.height, 0)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        positionedScrollView = true
    }

    private func makeLODViews() -> [NSView] {
        configureDistanceField(level0Field, identifier: "LODLevel0DistanceField")
        configureDistanceField(level1Field, identifier: "LODLevel1DistanceField")
        configureDistanceField(maximumField, identifier: "LODMaximumDistanceField")
        configureDistanceField(treeField, identifier: "LODTreeDistanceField")
        lodStatusLabel.font = .systemFont(ofSize: 11)
        lodStatusLabel.textColor = .secondaryLabelColor
        lodStatusLabel.widthAnchor.constraint(equalToConstant: 272).isActive = true

        let applyButton = NSButton(
            title: "Apply",
            target: self,
            action: #selector(applyLODDistances)
        )
        applyButton.setAccessibilityIdentifier("LODApplyButton")
        let resetButton = NSButton(
            title: "Use Skyrim INI",
            target: self,
            action: #selector(resetLODDistances)
        )
        resetButton.setAccessibilityIdentifier("LODResetButton")
        let buttons = NSStackView(views: [resetButton, applyButton])
        buttons.orientation = .horizontal
        return [
            Self.caption("Distant LOD (world units)"),
            Self.distanceRow("L4 maximum", field: level0Field),
            Self.distanceRow("L8 maximum", field: level1Field),
            Self.distanceRow("Far maximum", field: maximumField),
            Self.distanceRow("Trees", field: treeField),
            buttons,
            lodStatusLabel
        ]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        syncQualitySelection()
        syncLODFields()
        syncWeatherMenu()
        syncTimeOfDay()
        syncParticleControls()
        syncPrecipitationControls()
        refreshStats()
    }

    /// Begins the live stats readout at 2 Hz. Idempotent; added to the common
    /// run-loop mode so the readout keeps ticking during menu/resize tracking.
    func startInspecting() {
        syncQualitySelection()
        syncWeatherMenu()
        syncTimeOfDay()
        syncParticleControls()
        syncPrecipitationControls()
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

    private func syncQualitySelection() {
        guard let provider, let idx = qualities.firstIndex(of: provider.shadowQuality) else {
            return
        }
        qualityControl.selectItem(at: idx)
    }

    private func syncLODFields() {
        guard let snapshot = provider?.terrainLODConfigurationSnapshot else { return }
        let configuration = snapshot.configuration
        level0Field.stringValue = Self.distanceString(configuration.level0Distance)
        level1Field.stringValue = Self.distanceString(configuration.level1Distance)
        maximumField.stringValue = Self.distanceString(configuration.maximumDistance)
        treeField.stringValue = Self.distanceString(configuration.treeLoadDistance)
        lodStatusLabel.textColor = .secondaryLabelColor
        lodStatusLabel.stringValue = "Source: \(snapshot.source). Apply rebuilds LOD live."
    }

    @objc private func qualityChanged() {
        let idx = qualityControl.indexOfSelectedItem
        guard qualities.indices.contains(idx) else { return }
        provider?.shadowQuality = qualities[idx]
        refreshStats()
        // Popup interaction grabbed first responder; hand it back so the game
        // view keeps receiving WASD/look without a manual click.
        provider?.refocusGameView()
    }
}

extension EnvironmentPanelViewController {
    @objc private func applyLODDistances() {
        guard
            let level0 = Float(level0Field.stringValue),
            let level1 = Float(level1Field.stringValue),
            let maximum = Float(maximumField.stringValue),
            let tree = Float(treeField.stringValue)
        else {
            showLODError("Enter numeric distances.")
            return
        }
        let configuration = TerrainLODConfiguration(
            level0Distance: level0,
            level1Distance: level1,
            maximumDistance: maximum,
            treeLoadDistance: tree
        )
        guard provider?.applyTerrainLODConfiguration(configuration) == true else {
            showLODError("Require 0 < L4 <= L8 <= Far; Trees > 0.")
            return
        }
        syncLODFields()
        provider?.refocusGameView()
    }

    @objc private func resetLODDistances() {
        provider?.resetTerrainLODConfiguration()
        syncLODFields()
        provider?.refocusGameView()
    }

    private func showLODError(_ message: String) {
        lodStatusLabel.textColor = .systemRed
        lodStatusLabel.stringValue = message
    }

    @objc private func statsTick() {
        refreshStats()
    }

    func refreshStats() {
        guard let provider else {
            statsLabel.stringValue = "Shadow stats unavailable."
            return
        }
        let stats = provider.shadowDrawStats
        let state = provider.shadowsActive ? "active" : "idle"
        statsLabel.stringValue = """
        Shadows: \(Self.title(for: provider.shadowQuality)) · \(state)
        Draw calls: \(stats.drawCalls)
        Drawn: \(stats.drawnInstances)  Culled: \(stats.culledInstances)
        Cascades: \(stats.cascadesRendered)
        CPU: \(String(format: "%.2f", provider.shadowUpdateMS)) ms
        \(weatherReadout())
        \(particleReadout())
        \(precipitationReadout())
        """
    }

    private static func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 15)
        return label
    }

    static func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        return label
    }

    private func configureDistanceField(
        _ field: NSTextField,
        identifier: String
    ) {
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.widthAnchor.constraint(equalToConstant: 105).isActive = true
        field.setAccessibilityIdentifier(identifier)
    }

    private static func distanceRow(_ label: String, field: NSTextField) -> NSStackView {
        let caption = NSTextField(labelWithString: label)
        caption.widthAnchor.constraint(equalToConstant: 145).isActive = true
        let row = NSStackView(views: [caption, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private static func distanceString(_ value: Float) -> String {
        String(format: "%.0f", value)
    }

    private static func title(for quality: ShadowQuality) -> String {
        switch quality {
        case .off: "Off"
        case .low: "Low"
        case .high: "High"
        }
    }
}
