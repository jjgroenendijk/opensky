// Game clock and Tamriel calendar: game seconds advance as wall delta x timescale.
// Deterministic; wall deltas come from `FrameSimClock`. Sources:
// <https://en.uesp.net/wiki/Lore:Calendar>, <https://en.uesp.net/wiki/Skyrim:Time>
// (start 17th of Last Seed 4E 201, timescale 20), <https://en.uesp.net/wiki/Skyrim:Console>.
// No source gives the GameHour default, so 13:00 stays. See docs/engine/game-clock.md.

import Foundation

/// Deterministic game clock: `totalGameSeconds` since 4E 0, 1st of Morning Star.
/// A `Double`, because the start is about 6.3e9 seconds in, where a `Float` step is ~512 s.
nonisolated public struct GameClock: Equatable, Sendable {
    /// Month names, 1-based order per UESP `Lore:Calendar`.
    public static let monthNames = [
        "Morning Star", "Sun's Dawn", "First Seed", "Rain's Hand",
        "Second Seed", "Midyear", "Sun's Height", "Last Seed",
        "Hearthfire", "Frostfall", "Sun's Dusk", "Evening Star"
    ]
    /// Days per month per UESP `Lore:Calendar` (Sun's Dawn has 28; the lore
    /// note about an occasional 29th day is not modelled — the game has no
    /// leap years).
    public static let monthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    public static let daysPerYear = monthLengths.reduce(0, +) // 365
    public static let secondsPerDay: Double = 86400
    public static let secondsPerHour: Double = 3600

    /// Vanilla `TimeScale` default per UESP `Skyrim:Console`.
    public static let defaultTimescale: Float = 20
    /// Accepted timescale range. The floor is vanilla's own (0 freezes game
    /// time; negative time never runs backwards). The ceiling is an OpenSky
    /// safety bound: at 10 000 one clamped 0.1 s frame delta advances game
    /// time by at most ~16.7 game-minutes, so a runaway global cannot skip
    /// months in a frame. Documented in docs/engine/game-clock.md.
    public static let timescaleRange: ClosedRange<Float> = 0 ... 10000

    /// Vanilla start date: 17th of Last Seed, 4E 201 (UESP `Skyrim:Time`).
    public static let vanillaStartYear = 201
    public static let vanillaStartMonth = 8
    public static let vanillaStartDay = 17
    /// OpenSky's default start hour (see the header note on GameHour).
    public static let defaultStartHour: Float = 13

    /// Editor ID of the timescale global, which stays a real global read
    /// through `GlobalResolution` — unlike the five projected time globals.
    public static let timescaleEditorID = "TimeScale"

    /// Game seconds since 4E 0, 1st of Morning Star, 00:00. Never negative.
    public private(set) var totalGameSeconds: Double

    /// Vanilla start moment at the default hour.
    public init() {
        self.init(hour: Self.defaultStartHour)
    }

    /// Vanilla start date at `hour`.
    public init(hour: Float) {
        self.init(
            year: Self.vanillaStartYear,
            month: Self.vanillaStartMonth,
            day: Self.vanillaStartDay,
            hour: hour
        )
    }

    /// Clock at an explicit calendar moment. Out-of-range fields clamp.
    public init(year: Int, month: Int, day: Int, hour: Float) {
        let clampedYear = max(0, year)
        let clampedMonth = min(max(month, 1), Self.monthNames.count)
        let clampedDay = min(max(day, 1), Self.monthLengths[clampedMonth - 1])
        let days = clampedYear * Self.daysPerYear
            + Self.dayOfYearOffset(month: clampedMonth) + (clampedDay - 1)
        totalGameSeconds = Double(days) * Self.secondsPerDay
            + Self.wrappedHourSeconds(hour)
    }

    /// Restores a clock from persisted state (the save file's CLOK chunk).
    /// Negative or non-finite input clamps to the epoch.
    public init(totalGameSeconds: Double) {
        self.totalGameSeconds = totalGameSeconds.isFinite ? max(0, totalGameSeconds) : 0
    }

    // MARK: - Advancement

    /// Advances game time by `wallDelta` real seconds at `timescale` game
    /// seconds per real second. Negative deltas are ignored; timescale clamps
    /// into `timescaleRange`. Pure arithmetic — pausing is the caller feeding
    /// a zero delta (`FrameSimClock` already does while paused).
    public mutating func advance(wallDelta: Float, timescale: Float) {
        let clampedScale = min(
            max(
                timescale.isFinite ? timescale : Self.defaultTimescale,
                Self.timescaleRange.lowerBound
            ),
            Self.timescaleRange.upperBound
        )
        guard wallDelta.isFinite, wallDelta > 0 else { return }
        totalGameSeconds += Double(wallDelta) * Double(clampedScale)
    }

    // MARK: - Derived calendar state

    private var totalDays: Int {
        Int(totalGameSeconds / Self.secondsPerDay)
    }

    /// Fractional hour of day in [0, 24).
    public var hourOfDay: Float {
        Float(totalGameSeconds.truncatingRemainder(dividingBy: Self.secondsPerDay)
            / Self.secondsPerHour)
    }

    /// 1-based day of month.
    public var day: Int {
        dayAndMonth().day
    }

    /// 1-based month (1 = Morning Star ... 12 = Evening Star).
    public var month: Int {
        dayAndMonth().month
    }

    public var monthName: String {
        Self.monthNames[month - 1]
    }

    /// 4th-era year number (201 = 4E 201).
    public var year: Int {
        totalDays / Self.daysPerYear
    }

    /// Days elapsed since the vanilla start date at 00:00, fractional. The
    /// reference is fixed so no extra state is needed; UESP documents only
    /// "days passed since starting the game", so 0-at-vanilla-start-midnight
    /// is OpenSky's documented choice.
    public var daysPassed: Float {
        Float((totalGameSeconds - Self.vanillaStartMidnightSeconds) / Self.secondsPerDay)
    }

    // MARK: - Scrubbing

    /// Sets the hour of day, keeping the date. 24 wraps to 0 of the same day.
    public mutating func setHour(_ hour: Float) {
        totalGameSeconds = Double(totalDays) * Self.secondsPerDay
            + Self.wrappedHourSeconds(hour)
    }

    /// Sets the day of month, keeping month, year and hour. Clamps into the
    /// current month's length.
    public mutating func setDay(_ newDay: Int) {
        setDate(year: year, month: month, day: newDay)
    }

    /// Sets the month, keeping year and hour and clamping the day into the
    /// new month's length.
    public mutating func setMonth(_ newMonth: Int) {
        setDate(year: year, month: newMonth, day: day)
    }

    /// Sets the 4th-era year, keeping month, day and hour.
    public mutating func setYear(_ newYear: Int) {
        setDate(year: newYear, month: month, day: day)
    }

    /// Moves the clock to `days` past the vanilla start date at 00:00, the
    /// inverse of `daysPassed`. Adding a whole number therefore keeps the
    /// hour, matching how the console global is used to wait days.
    public mutating func setDaysPassed(_ days: Float) {
        guard days.isFinite else { return }
        totalGameSeconds = max(
            0, Self.vanillaStartMidnightSeconds + Double(days) * Self.secondsPerDay
        )
    }

    private mutating func setDate(year: Int, month: Int, day: Int) {
        let hour = hourOfDay
        self = GameClock(year: year, month: month, day: day, hour: hour)
    }

    // MARK: - Helpers

    private func dayAndMonth() -> (month: Int, day: Int) {
        var remaining = totalDays % Self.daysPerYear
        for (index, length) in Self.monthLengths.enumerated() {
            if remaining < length {
                return (month: index + 1, day: remaining + 1)
            }
            remaining -= length
        }
        // Unreachable: remaining < daysPerYear by construction.
        return (month: Self.monthLengths.count, day: Self.monthLengths[11])
    }

    /// Days into the year before `month` begins (month is 1-based).
    private static func dayOfYearOffset(month: Int) -> Int {
        monthLengths.prefix(month - 1).reduce(0, +)
    }

    /// Seconds-of-day for an hour scrub: non-finite -> 0, then wrapped into
    /// [0, 24) so 24:00 means 00:00 (the slider's upper bound).
    private static func wrappedHourSeconds(_ hour: Float) -> Double {
        guard hour.isFinite else { return 0 }
        let wrapped = Double(hour).truncatingRemainder(dividingBy: 24)
        return (wrapped < 0 ? wrapped + 24 : wrapped) * secondsPerHour
    }

    /// `totalGameSeconds` of the vanilla start date at 00:00 — the fixed
    /// reference `daysPassed` counts from.
    private static let vanillaStartMidnightSeconds: Double = {
        let days = vanillaStartYear * daysPerYear
            + dayOfYearOffset(month: vanillaStartMonth) + (vanillaStartDay - 1)
        return Double(days) * secondsPerDay
    }()
}

// MARK: - Time globals

nonisolated extension GameClock {
    /// The five vanilla globals the clock owns. Their values are projected
    /// from the clock on read and a write to one of them moves the clock —
    /// one source of truth, no drift (docs/engine/game-clock.md). `TimeScale`
    /// is deliberately absent: it stays an ordinary global override.
    public enum TimeGlobal: CaseIterable, Sendable {
        case gameHour, gameDaysPassed, gameDay, gameMonth, gameYear

        public var editorID: String {
            switch self {
            case .gameHour: "GameHour"
            case .gameDaysPassed: "GameDaysPassed"
            case .gameDay: "GameDay"
            case .gameMonth: "GameMonth"
            case .gameYear: "GameYear"
            }
        }

        /// Case-insensitive, matching how globals are addressed everywhere.
        public init?(editorID: String) {
            let lowered = editorID.lowercased()
            guard
                let match = Self.allCases.first(
                    where: { $0.editorID.lowercased() == lowered }
                ) else { return nil }
            self = match
        }
    }

    /// The value the named time global reads as right now.
    public func projectedValue(_ global: TimeGlobal) -> Float {
        switch global {
        case .gameHour: hourOfDay
        case .gameDaysPassed: daysPassed
        case .gameDay: Float(day)
        case .gameMonth: Float(month)
        case .gameYear: Float(year)
        }
    }

    /// Applies a write to a time global by moving the clock. Non-finite
    /// values are ignored; integer-valued globals round half away from zero,
    /// matching `GlobalValue`'s coercion rule.
    public mutating func setProjectedValue(_ value: Float, for global: TimeGlobal) {
        guard value.isFinite else { return }
        switch global {
        case .gameHour: setHour(value)
        case .gameDaysPassed: setDaysPassed(value)
        case .gameDay: setDay(Int(value.rounded(.toNearestOrAwayFromZero)))
        case .gameMonth: setMonth(Int(value.rounded(.toNearestOrAwayFromZero)))
        case .gameYear: setYear(Int(value.rounded(.toNearestOrAwayFromZero)))
        }
    }
}
