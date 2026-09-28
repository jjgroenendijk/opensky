// World > Runtime State > Time section (M10.2.1): scrubs the game clock — hour
// and full calendar date — sets the timescale the clock advances at, and states
// whether the world simulation is paused.
//
// Pause is a readout, not a control, and deliberately so. `Renderer.worldSimPaused`
// is owned by `MenuModeController`: the menu drives it, and every sim clock in
// the renderer reads it. A checkbox here would be silently overwritten the next
// time the menu opened or closed, which is a worse surface than an honest
// readout. World > System Menu owns the toggle; this section reports what it
// did, because a clock that appears stuck is otherwise inexplicable.
//
// The one setting this section owns is the timescale, which is the `TimeScale`
// global rather than a clock property — so the timescale is what makes this
// section overridden, and resetting it writes the vanilla default back. Time
// passing is not an override: a clock that has advanced is a world that has
// been played, not a knob left in a non-default position.

import AppKit

final class RuntimeStateTimeSection: PanelSectionViewController {
    weak var provider: (any RuntimeStateControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let hourControl = NSSlider(value: 12, minValue: 0, maxValue: 24, target: nil, action: nil)
    let dayControl = NSTextField()
    let monthControl = NSPopUpButton()
    let yearControl = NSTextField()
    let applyDateControl = NSButton(title: "Apply date", target: nil, action: nil)
    let timescaleControl = NSTextField()
    let applyTimescaleControl = NSButton(title: "Apply", target: nil, action: nil)

    private let hourValueLabel = PanelComponents.valueLabel(width: 56)
    private let statsLabel = PanelComponents.statsLabel(identifier: "RuntimeStateTimeStatsLabel")
    /// Result of the most recent apply, kept across ticker refreshes so the
    /// readout does not erase what the user just did.
    private var lastActionText = "No time change applied yet."

    override var sectionTitle: String {
        "Time"
    }

    override var sectionIdentifier: String {
        "runtimeStateTime"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    /// The timescale is the section's only setting, so it alone decides
    /// overridden-ness. Shared with the destination-level reset in
    /// `RuntimeStateResetSection`.
    static func isOverridden(provider: (any RuntimeStateControlProviding)?) -> Bool {
        guard let provider else { return false }
        return provider.runtimeStateClock.timescale != GameClock.defaultTimescale
    }

    static func resetToDefaults(provider: (any RuntimeStateControlProviding)?) {
        provider?.setGameTimescale(GameClock.defaultTimescale)
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.group([
                PanelComponents.caption("Hour of day"),
                PanelComponents.sliderRow(slider: hourControl, valueLabel: hourValueLabel)
            ]),
            PanelComponents.group([
                PanelComponents.note(
                    "Scrubbing writes the GameHour, GameDay, GameMonth and GameYear globals, "
                        + "which the clock owns, so every scrub appears in the journal."
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Day", captionWidth: 60, field: dayControl
                ),
                PanelComponents.caption("Month"),
                monthControl,
                PanelComponents.labeledFieldRow(
                    caption: "Year", captionWidth: 60, field: yearControl
                ),
                PanelComponents.buttonRow([applyDateControl])
            ]),
            PanelComponents.group([
                PanelComponents.note(
                    "Timescale is the TimeScale global: game seconds per real second. "
                        + "Vanilla is \(Int(GameClock.defaultTimescale))."
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Timescale", captionWidth: 70, field: timescaleControl
                ),
                PanelComponents.buttonRow([applyTimescaleControl])
            ]),
            statsLabel
        ]
    }

    private func configureControls() {
        PanelComponents.configureSlider(
            hourControl, target: self, action: #selector(hourChanged),
            identifier: "RuntimeStateHourControl", width: 180
        )
        PanelComponents.configureTextField(
            dayControl, identifier: "RuntimeStateDayControl", width: 60, placeholder: "17"
        )
        PanelComponents.configurePopUp(
            monthControl, target: self, action: #selector(monthChanged),
            identifier: "RuntimeStateMonthControl", width: 200
        )
        monthControl.addItems(withTitles: GameClock.monthNames)
        PanelComponents.configureTextField(
            yearControl, identifier: "RuntimeStateYearControl", width: 60, placeholder: "201"
        )
        PanelComponents.configureButton(
            applyDateControl, target: self, action: #selector(applyDate),
            identifier: "RuntimeStateApplyDateControl"
        )
        PanelComponents.configureTextField(
            timescaleControl, identifier: "RuntimeStateTimescaleControl", width: 70,
            placeholder: String(Int(GameClock.defaultTimescale))
        )
        PanelComponents.configureButton(
            applyTimescaleControl, target: self, action: #selector(applyTimescale),
            identifier: "RuntimeStateApplyTimescaleControl"
        )
    }

    // MARK: Actions

    @objc private func hourChanged() {
        provider?.setGameClockHour(Float(hourControl.doubleValue))
        finishInteraction(refocusOnMouseUpOnly: true)
    }

    /// The month popup does not apply on its own: day, month and year are one
    /// date, and applying a month while a partly typed day sits beside it would
    /// move the clock somewhere the user never asked for.
    @objc private func monthChanged() {
        refreshReadout()
    }

    @objc private func applyDate() {
        let clock = provider?.runtimeStateClock ?? .empty
        provider?.setGameClockDate(
            day: Int(dayControl.stringValue) ?? clock.day,
            month: monthControl.indexOfSelectedItem + 1,
            year: Int(yearControl.stringValue) ?? clock.year
        )
        syncControls()
        finishInteraction()
    }

    @objc private func applyTimescale() {
        guard let value = Float(timescaleControl.stringValue) else {
            lastActionText = "Timescale must be a number."
            finishInteraction()
            return
        }
        lastActionText = provider?.setGameTimescale(value) == true
            ? "Timescale set to \(RuntimeStateNumberText.text(value))."
            : "No TimeScale global is loaded, so the timescale is unchanged."
        syncControls()
        finishInteraction()
    }

    // MARK: Sync and readout

    override func syncControls() {
        guard let provider else { return }
        let clock = provider.runtimeStateClock
        hourControl.doubleValue = Double(clock.hourOfDay)
        dayControl.stringValue = String(clock.day)
        monthControl.selectItem(at: min(max(0, clock.month - 1), monthControl.numberOfItems - 1))
        yearControl.stringValue = String(clock.year)
        timescaleControl.stringValue = RuntimeStateNumberText.text(clock.timescale)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Runtime state: unavailable"
            hourValueLabel.stringValue = ""
            return
        }
        let clock = provider.runtimeStateClock
        hourValueLabel.stringValue = clock.timeText
        statsLabel.stringValue = [
            "\(clock.timeText)  \(clock.dateText)",
            "Days passed: \(String(format: "%.2f", clock.daysPassed))"
                + "  Timescale: \(RuntimeStateNumberText.text(clock.timescale))",
            "World simulation: \(clock.pauseText)",
            lastActionText
        ].joined(separator: "\n")
    }
}
