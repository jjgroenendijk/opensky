// The date line the menus show, such as "Sundas, 1:05 PM, 17th of Last Seed, 4E 201".
// Weekday names from UESP "Lore:Calendar"; the layout follows the wait menu.

import Foundation

nonisolated extension GameClock {
    /// 0 = Sundas, as `weekday` counts.
    public static let weekdayNames = [
        "Sundas", "Morndas", "Tirdas", "Middas", "Turdas", "Fredas", "Loredas"
    ]

    public var menuDateText: String {
        let minutes = Int(hourOfDay * 60)
        let hour = minutes / 60
        let clockHour = hour % 12 == 0 ? 12 : hour % 12
        let time = String(format: "%d:%02d %@", clockHour, minutes % 60, hour < 12 ? "AM" : "PM")
        return "\(Self.weekdayNames[weekday]), \(time), \(Self.ordinal(day)) of \(monthName), "
            + "4E \(year)"
    }

    /// "1st", "2nd", "3rd", "11th", "21st".
    static func ordinal(_ number: Int) -> String {
        let suffix = switch (number % 10, number % 100) {
        case (_, 11 ... 13): "th"
        case (1, _): "st"
        case (2, _): "nd"
        case (3, _): "rd"
        default: "th"
        }
        return "\(number)\(suffix)"
    }
}
