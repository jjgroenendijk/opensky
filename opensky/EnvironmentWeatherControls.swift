// World > Environment > Weather force/pause/clock controls (M7.4.2).

import AppKit

extension EnvironmentPanelViewController {
    private static var autoWeatherTitle: String {
        "Auto"
    }

    func makeWeatherViews() -> [NSView] {
        weatherControl.target = self
        weatherControl.action = #selector(weatherChanged)
        weatherControl.setAccessibilityIdentifier("WeatherControl")

        configurePreset(clearWeatherControl, preset: .clear, identifier: "ClearWeatherControl")
        configurePreset(rainWeatherControl, preset: .rain, identifier: "RainWeatherControl")
        configurePreset(snowWeatherControl, preset: .snow, identifier: "SnowWeatherControl")
        let presets = NSStackView(views: [
            clearWeatherControl, rainWeatherControl, snowWeatherControl
        ])
        presets.orientation = .horizontal
        presets.alignment = .centerY
        presets.heightAnchor.constraint(equalToConstant: 24).isActive = true

        weatherTransitionsPausedControl.target = self
        weatherTransitionsPausedControl.action = #selector(weatherPauseChanged)
        weatherTransitionsPausedControl.setAccessibilityIdentifier(
            "WeatherTransitionsPausedControl"
        )
        weatherTransitionsPausedControl.heightAnchor.constraint(equalToConstant: 20).isActive = true

        timeControl.target = self
        timeControl.action = #selector(timeOfDayChanged)
        timeControl.isContinuous = true
        timeControl.setAccessibilityIdentifier("TimeOfDayControl")
        timeControl.widthAnchor.constraint(equalToConstant: 272).isActive = true
        timeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.setAccessibilityIdentifier("TimeOfDayLabel")

        return [
            Self.caption("Weather"), weatherControl, presets, weatherTransitionsPausedControl,
            Self.caption("Time of day"), timeControl, timeLabel
        ]
    }

    private func configurePreset(
        _ button: NSButton,
        preset: WeatherPreset,
        identifier: String
    ) {
        button.target = self
        button.action = switch preset {
        case .clear: #selector(forceClearWeather)
        case .rain: #selector(forceRainWeather)
        case .snow: #selector(forceSnowWeather)
        }
        button.setAccessibilityIdentifier(identifier)
    }

    /// Rebuilds the weather popup (Auto + selectable editor IDs) and selects
    /// the weather in effect. No weather data -> Auto only, disabled.
    func syncWeatherMenu() {
        let names = weatherProvider?.selectableWeatherNames ?? []
        weatherControl.removeAllItems()
        weatherControl.addItem(withTitle: Self.autoWeatherTitle)
        weatherControl.addItems(withTitles: names)
        weatherControl.isEnabled = !names.isEmpty
        for button in [clearWeatherControl, rainWeatherControl, snowWeatherControl] {
            button.isEnabled = !names.isEmpty
        }
        weatherTransitionsPausedControl.isEnabled = !names.isEmpty
        weatherTransitionsPausedControl.state = weatherProvider?.weatherTransitionsPaused == true
            ? .on : .off
        let current = weatherProvider?.currentWeatherName
        if let current, weatherControl.itemTitles.contains(current) {
            weatherControl.selectItem(withTitle: current)
        } else {
            weatherControl.selectItem(withTitle: Self.autoWeatherTitle)
        }
    }

    @objc private func weatherChanged() {
        let title = weatherControl.titleOfSelectedItem
        weatherProvider?.forceWeather(named: title == Self.autoWeatherTitle ? nil : title)
        finishWeatherInteraction()
    }

    @objc private func forceClearWeather() {
        forceWeather(.clear)
    }

    @objc private func forceRainWeather() {
        forceWeather(.rain)
    }

    @objc private func forceSnowWeather() {
        forceWeather(.snow)
    }

    private func forceWeather(_ preset: WeatherPreset) {
        weatherProvider?.forceWeather(preset)
        syncWeatherMenu()
        finishWeatherInteraction()
    }

    @objc private func weatherPauseChanged() {
        weatherProvider?.weatherTransitionsPaused = weatherTransitionsPausedControl.state == .on
        finishWeatherInteraction()
    }

    private func finishWeatherInteraction() {
        refreshStats()
        provider?.refocusGameView()
    }

    /// Pulls the live renderer's clock onto the slider + label. No weather
    /// provider -> the slider stays disabled at the stored default.
    func syncTimeOfDay() {
        guard let weatherProvider else {
            timeControl.isEnabled = false
            timeLabel.stringValue = Self.timeText(TimeOfDaySettings.load())
            return
        }
        timeControl.isEnabled = true
        timeControl.doubleValue = Double(weatherProvider.timeOfDay)
        timeLabel.stringValue = Self.timeText(weatherProvider.timeOfDay)
    }

    @objc private func timeOfDayChanged() {
        let hour = Float(timeControl.doubleValue)
        weatherProvider?.timeOfDay = hour
        timeLabel.stringValue = Self.timeText(hour)
        if NSApp.currentEvent?.type == .leftMouseUp {
            provider?.refocusGameView()
        }
    }

    /// "HH:MM" from a fractional game-hour.
    private static func timeText(_ hour: Float) -> String {
        let wrapped = hour.truncatingRemainder(dividingBy: 24)
        let normalized = wrapped < 0 ? wrapped + 24 : wrapped
        let hours = Int(normalized)
        let minutes = Int((normalized - Float(hours)) * 60) % 60
        return String(format: "Time: %02d:%02d", hours, minutes)
    }

    func weatherReadout() -> String {
        guard let weatherProvider else { return "Weather: unavailable" }
        let name = weatherProvider.currentWeatherName ?? "none"
        let wind = weatherProvider.windState
        let heading = Int((atan2(wind.direction.y, wind.direction.x) * 180 / .pi + 360)
            .truncatingRemainder(dividingBy: 360))
        let progress = Int((weatherProvider.weatherTransitionFraction * 100).rounded())
        let paused = weatherProvider.weatherTransitionsPaused ? " · paused" : ""
        return """
        Weather: \(name) (blend \(progress)%)\(paused)
        Wind: \(String(format: "%.2f", wind.speed)) @ \(heading)°
        """
    }
}
