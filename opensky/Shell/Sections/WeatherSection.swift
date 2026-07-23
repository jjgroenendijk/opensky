// World > Environment > Weather section: force/pause/clock controls + live
// weather + wind readout (issue #98 decomposition of EnvironmentWeatherControls).

import AppKit

final class WeatherSection: PanelSectionViewController {
    weak var provider: (any WeatherControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    let weatherControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let clearControl = NSButton(title: "Clear", target: nil, action: nil)
    let rainControl = NSButton(title: "Rain", target: nil, action: nil)
    let snowControl = NSButton(title: "Snow", target: nil, action: nil)
    let transitionsPausedControl = NSButton(
        checkboxWithTitle: "Pause transitions", target: nil, action: nil
    )
    let timeControl = NSSlider(
        value: Double(TimeOfDaySettings.fallback),
        minValue: Double(TimeOfDaySettings.range.lowerBound),
        maxValue: Double(TimeOfDaySettings.range.upperBound),
        target: nil,
        action: nil
    )
    private let timeLabel = NSTextField(labelWithString: "")
    private let statsLabel = PanelComponents.statsLabel(identifier: "WeatherStatsLabel")

    override var sectionTitle: String {
        "Weather"
    }

    override var sectionIdentifier: String {
        "weather"
    }

    private static let autoWeatherTitle = "Auto"

    override func makeContentViews() -> [NSView] {
        enabledControl.target = self
        enabledControl.action = #selector(enabledChanged)
        enabledControl.setAccessibilityIdentifier("WeatherEnabledControl")
        weatherControl.target = self
        weatherControl.action = #selector(weatherChanged)
        weatherControl.setAccessibilityIdentifier("WeatherControl")

        configurePreset(clearControl, action: #selector(forceClear), id: "ClearWeatherControl")
        configurePreset(rainControl, action: #selector(forceRain), id: "RainWeatherControl")
        configurePreset(snowControl, action: #selector(forceSnow), id: "SnowWeatherControl")
        let presets = PanelComponents.buttonRow([clearControl, rainControl, snowControl])
        presets.heightAnchor.constraint(equalToConstant: 24).isActive = true

        transitionsPausedControl.target = self
        transitionsPausedControl.action = #selector(pauseChanged)
        transitionsPausedControl.setAccessibilityIdentifier("WeatherTransitionsPausedControl")
        transitionsPausedControl.heightAnchor.constraint(equalToConstant: 20).isActive = true

        timeControl.target = self
        timeControl.action = #selector(timeChanged)
        timeControl.isContinuous = true
        timeControl.setAccessibilityIdentifier("TimeOfDayControl")
        timeControl.widthAnchor.constraint(
            equalToConstant: PanelMetrics.contentWidth
        ).isActive = true
        timeLabel.font = PanelMetrics.monoFont
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.setAccessibilityIdentifier("TimeOfDayLabel")

        return [
            enabledControl, weatherControl, presets, transitionsPausedControl,
            PanelComponents.caption("Time of day"), timeControl, timeLabel, statsLabel
        ]
    }

    private func configurePreset(_ button: NSButton, action: Selector, id: String) {
        button.target = self
        button.action = action
        button.setAccessibilityIdentifier(id)
    }

    override func syncControls() {
        syncWeatherMenu()
        syncTimeOfDay()
    }

    /// Rebuilds the weather popup (Auto + selectable editor IDs) and selects the
    /// weather in effect. No weather data -> Auto only, disabled.
    private func syncWeatherMenu() {
        let names = provider?.selectableWeatherNames ?? []
        weatherControl.removeAllItems()
        weatherControl.addItem(withTitle: Self.autoWeatherTitle)
        weatherControl.addItems(withTitles: names)
        weatherControl.isEnabled = !names.isEmpty
        enabledControl.isEnabled = !names.isEmpty
        enabledControl.state = provider?.weatherEnabled == true ? .on : .off
        for button in [clearControl, rainControl, snowControl] {
            button.isEnabled = !names.isEmpty
        }
        transitionsPausedControl.isEnabled = !names.isEmpty
        transitionsPausedControl.state = provider?.weatherTransitionsPaused == true ? .on : .off
        let current = provider?.currentWeatherName
        if let current, weatherControl.itemTitles.contains(current) {
            weatherControl.selectItem(withTitle: current)
        } else {
            weatherControl.selectItem(withTitle: Self.autoWeatherTitle)
        }
    }

    /// Pulls the live renderer's clock onto the slider + label. No provider ->
    /// the slider stays disabled at the stored default.
    private func syncTimeOfDay() {
        guard let provider else {
            timeControl.isEnabled = false
            timeLabel.stringValue = Self.timeText(TimeOfDaySettings.load())
            return
        }
        timeControl.isEnabled = true
        timeControl.doubleValue = Double(provider.timeOfDay)
        timeLabel.stringValue = Self.timeText(provider.timeOfDay)
    }

    @objc private func enabledChanged() {
        provider?.weatherEnabled = enabledControl.state == .on
        finishInteraction()
    }

    @objc private func weatherChanged() {
        let title = weatherControl.titleOfSelectedItem
        provider?.forceWeather(named: title == Self.autoWeatherTitle ? nil : title)
        finishInteraction()
    }

    @objc private func forceClear() {
        forcePreset(.clear)
    }

    @objc private func forceRain() {
        forcePreset(.rain)
    }

    @objc private func forceSnow() {
        forcePreset(.snow)
    }

    private func forcePreset(_ preset: WeatherPreset) {
        provider?.forceWeather(preset)
        syncWeatherMenu()
        finishInteraction()
    }

    @objc private func pauseChanged() {
        provider?.weatherTransitionsPaused = transitionsPausedControl.state == .on
        finishInteraction()
    }

    @objc private func timeChanged() {
        let hour = Float(timeControl.doubleValue)
        provider?.timeOfDay = hour
        timeLabel.stringValue = Self.timeText(hour)
        finishInteraction(refocusOnMouseUpOnly: true)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Weather: unavailable"
            return
        }
        guard provider.weatherEnabled else {
            statsLabel.stringValue = "Weather: disabled"
            return
        }
        let name = provider.currentWeatherName ?? "none"
        let wind = provider.windState
        let heading = Int((atan2(wind.direction.y, wind.direction.x) * 180 / .pi + 360)
            .truncatingRemainder(dividingBy: 360))
        let progress = Int((provider.weatherTransitionFraction * 100).rounded())
        let paused = provider.weatherTransitionsPaused ? " · paused" : ""
        statsLabel.stringValue = """
        Weather: \(name) (blend \(progress)%)\(paused)
        Wind: \(String(format: "%.2f", wind.speed)) @ \(heading)°
        """
    }

    /// "HH:MM" from a fractional game-hour.
    private static func timeText(_ hour: Float) -> String {
        let wrapped = hour.truncatingRemainder(dividingBy: 24)
        let normalized = wrapped < 0 ? wrapped + 24 : wrapped
        let hours = Int(normalized)
        let minutes = Int((normalized - Float(hours)) * 60) % 60
        return String(format: "Time: %02d:%02d", hours, minutes)
    }
}
