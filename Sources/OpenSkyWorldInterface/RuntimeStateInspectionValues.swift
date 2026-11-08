import Foundation
import OpenSkyGameData
public import OpenSkyWorldState

/// One game-time sample: calendar, timescale and pause. The timescale is the `TimeScale`
/// GLOB, not a clock property, but it belongs in the same sample.
nonisolated public struct RuntimeStateClockSnapshot: Equatable, Sendable {
    /// Fractional hour of day in [0, 24).
    public let hourOfDay: Float
    /// One-based day of the month.
    public let day: Int
    public let monthName: String
    /// Fourth-era year, so 201 reads as 4E 201.
    public let year: Int
    /// Fractional days since the vanilla start date at midnight.
    public let daysPassed: Float
    /// Game seconds per wall-clock second, from the `TimeScale` global.
    public let timescale: Float

    public init(
        clock: GameClock, timescale: Float
    ) {
        hourOfDay = clock.hourOfDay
        day = clock.day
        monthName = clock.monthName
        year = clock.year
        daysPassed = clock.daysPassed
        self.timescale = timescale
    }

    /// Twenty-four-hour wall spelling of `hourOfDay`, minutes truncated rather
    /// than rounded so a readout never shows the next hour before it arrives.
    public var timeText: String {
        let clamped = hourOfDay.isFinite ? min(max(0, hourOfDay), 24) : 0
        let hour = Int(clamped.rounded(.down))
        let minute = Int(((clamped - Float(hour)) * 60).rounded(.down))
        return unsafe String(format: "%02d:%02d", hour, min(minute, 59))
    }

    /// Calendar spelling, in the in-game order: day, month name, era and year.
    public var dateText: String {
        "\(day) \(monthName), 4E \(year)"
    }
}

/// One global: authored value, current value, and whether an override was written. Not
/// `defaultValue != currentValue`: writing the same value records an override, and the
/// clock-projected time globals differ without one.
nonisolated public struct RuntimeStateGlobalSnapshot: Equatable, Sendable {
    public let editorID: String
    public let defaultValue: Float
    public let currentValue: Float
    public let isOverridden: Bool

    public init(
        editorID: String,
        defaultValue: Float,
        currentValue: Float,
        isOverridden: Bool
    ) {
        self.editorID = editorID
        self.defaultValue = defaultValue
        self.currentValue = currentValue
        self.isOverridden = isOverridden
    }
}
