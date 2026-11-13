// The words of the `<Global...>` text replacement tags, the text a tag shows when its
// value is missing, and the word before an alternative objective.
// See docs/engine/journal.md#text-replacement.

public import OpenSkyGameData

nonisolated public enum TextReplacementText: String, GameSettingTextKey {
    case invalidTag = "sInvalidTagString"
    /// Put before an objective that is an alternative to the one above it.
    case or = "sOr"
    case hours = "sTimeHours"
    case minutes = "sTimeMinutes"
    case midnight = "sTimeSpanMidnight"
    case night = "sTimeSpanNight"
    case sunrise = "sTimeSpanSunrise"
    case morning = "sTimeSpanMorning"
    case afternoon = "sTimeSpanAfternoon"
    case sunset = "sTimeSpanSunset"
    case evening = "sTimeSpanEvening"

    public var fallback: String {
        switch self {
        case .invalidTag: "[...]"
        case .or: "OR"
        case .hours: "Hours"
        case .minutes: "Minutes"
        case .midnight: "Midnight"
        case .night: "Night"
        case .sunrise: "Sunrise"
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .sunset: "Sunset"
        case .evening: "Evening"
        }
    }

    /// Each span's first hour and the hour it ends; a span may wrap past midnight.
    public static let spans: [(text: Self, hours: (start: Float, end: Float))] = [
        (.midnight, (23, 1)), (.night, (1, 5)), (.sunrise, (5, 8)), (.morning, (8, 12)),
        (.afternoon, (12, 17)), (.sunset, (17, 19)), (.evening, (19, 23))
    ]

    /// The span that holds `hour`, from 0 up to 24.
    public static func span(atHour hour: Float) -> Self {
        let wrapped = hour.truncatingRemainder(dividingBy: 24)
        let positive = wrapped < 0 ? wrapped + 24 : wrapped
        for span in spans {
            let (start, end) = span.hours
            let inside = start <= end
                ? (start ..< end).contains(positive)
                : positive >= start || positive < end
            if inside {
                return span.text
            }
        }
        return .midnight
    }
}
