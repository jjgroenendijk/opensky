// The words of the in-game date line, "Sundas, 8:00 AM, 17th of Last Seed, 4E 201",
// from the string settings. See docs/engine/game-clock.md.

import Foundation

nonisolated public struct CalendarTexts: Equatable, Sendable {
    /// `sMonthJanuary` to `sMonthDecember`; the game names the Tamriel months there.
    public var months = Self.monthSettings
    /// `sDaySunday` to `sDaySaturday`, in `GameClock.weekday` order.
    public var weekdays = Self.weekdaySettings
    public var am = "sTimeAM"
    public var pm = "sTimePM"
    /// `sFirstOrdSuffix`, `sSecondOrdSuffix`, `sThirdOrdSuffix`, and `sDefaultOrdSuffix`.
    public var ordinalSuffixes = ["sFirstOrdSuffix", "sSecondOrdSuffix", "sThirdOrdSuffix"]
    public var defaultOrdinalSuffix = "sDefaultOrdSuffix"
    /// `sOf`, which carries its own spaces.
    public var of = "sOf"

    public static let vanilla = Self()
    static let monthSettings = [
        "January", "February", "March", "April", "May", "June", "July", "August",
        "September", "October", "November", "December"
    ].map { "sMonth\($0)" }
    static let weekdaySettings = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
    ].map { "sDay\($0)" }

    public init() {}

    /// `day` with its suffix. English rules: 11 to 13 take the default suffix.
    public func ordinal(_ day: Int) -> String {
        let teen = (11 ... 13).contains(day % 100)
        let last = day % 10
        let suffix = !teen && (1 ... 3).contains(last)
            ? ordinalSuffixes[last - 1] : defaultOrdinalSuffix
        return "\(day)\(suffix)"
    }

    /// The date line the wait menu and the journal show.
    public func dateLine(
        weekday: Int, hourOfDay: Float, day: Int, month: Int, year: Int
    ) -> String {
        let clamped = hourOfDay.isFinite ? min(max(0, hourOfDay), 23.999) : 0
        let hour = Int(clamped.rounded(.down))
        let minute = min(59, Int(((clamped - Float(hour)) * 60).rounded(.down)))
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let time = "\(twelve):" + String(format: "%02d", minute) + " " + (hour < 12 ? am : pm)
        let weekdayName = weekdays[min(max(weekday, 0), weekdays.count - 1)]
        let monthName = months[min(max(month, 1), months.count) - 1]
        return "\(weekdayName), \(time), \(ordinal(day))\(of)\(monthName), 4E \(year)"
    }

    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var settings = vanilla
        func word(_ editorID: String) -> String {
            store.text(editorID).flatMap { text($0) } ?? editorID
        }
        settings.months = monthSettings.map(word)
        settings.weekdays = weekdaySettings.map(word)
        settings.am = word("sTimeAM")
        settings.pm = word("sTimePM")
        settings.ordinalSuffixes = settings.ordinalSuffixes.map(word)
        settings.defaultOrdinalSuffix = word("sDefaultOrdSuffix")
        settings.of = word("sOf")
        return settings
    }
}
