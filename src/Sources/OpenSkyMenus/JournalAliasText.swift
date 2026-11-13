// Tag substitution in journal and message text. Vanilla writes `<Alias=Prisoner>`,
// `<Alias.ShortName=Jail>`, or `<Global=FFR04NirnCount>`
// (<https://ck.uesp.net/wiki/Text_Replacement>). An alias or global with no value shows
// `sInvalidTagString`; a tag of another family, or a subtag OpenSky does not know, stays
// as written, as that page says.

import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMenusInterface
import OpenSkyWorldState

nonisolated extension QuestAliasNaming {
    /// What one tag becomes.
    private enum TagResult {
        case text(String)
        /// The tag's alias or global has no value.
        case missing
        /// Not a tag OpenSky reads; it stays as written.
        case unread
    }

    private func replacement(for body: Substring, in quest: Quest) -> TagResult {
        guard let equals = body.firstIndex(of: "=") else { return .unread }
        let parts = body[..<equals].split(separator: ".", maxSplits: 1)
        let name = body[body.index(after: equals)...]
        guard !name.isEmpty else { return .unread }
        var subtag = parts.count > 1 ? parts[1].lowercased() : ""
        let capitalised = subtag.hasSuffix("cap")
        if capitalised {
            subtag.removeLast(3)
        }
        let result = switch (parts.first ?? "").lowercased() {
        case Self.aliasKeyword: aliasText(name: name, subtag: subtag, in: quest)
        case "global": globalText(name: String(name), subtag: subtag)
        default: TagResult.unread
        }
        guard capitalised, case let .text(text) = result else { return result }
        return .text(text.prefix(1).uppercased() + text.dropFirst())
    }

    private func aliasText(name: Substring, subtag: String, in quest: Quest) -> TagResult {
        guard let fill = fill(named: name.lowercased(), in: quest) else { return .missing }
        guard let pronoun = PronounText.pair(subtag: subtag) else { return .text(fill.name) }
        guard let female = fill.isFemale else { return .missing }
        return .text(pronouns[female ? pronoun.female : pronoun.male])
    }

    private func globalText(name: String, subtag: String) -> TagResult {
        guard let value = global(name), value.isFinite else { return .missing }
        if subtag.isEmpty {
            return .text(Self.number(value))
        }
        if subtag == "time" {
            return .text(timerText(hours: value))
        }
        var clock = GameClock()
        clock.setDaysPassed(value)
        return calendarText(clock: clock, subtag: subtag).map(TagResult.text) ?? .unread
    }

    /// A whole value prints as an integer; a fraction to two places, as the wiki gives
    /// for a float global.
    static func number(_ value: Float) -> String {
        value == value.rounded() ? String(Int(value)) : fixed(value, places: 2)
    }

    /// `value` with exactly `places` decimals, without the C formatting functions.
    static func fixed(_ value: Float, places: Int) -> String {
        var scale = 1
        for _ in 0 ..< places {
            scale *= 10
        }
        let scaled = Int((abs(value) * Float(scale)).rounded())
        let sign = value < 0 && scaled != 0 ? "-" : ""
        let fraction = String(scaled % scale)
        let padding = String(repeating: "0", count: max(0, places - fraction.count))
        return "\(sign)\(scaled / scale).\(padding)\(fraction)"
    }

    /// `<Global.Time=...>`: hours with one decimal from one hour up, else minutes.
    private func timerText(hours: Float) -> String {
        if hours >= 1 {
            return "\(Self.fixed(hours, places: 1)) " + replacementTexts[.hours]
        }
        let minutes = hours > 0 ? Int((hours * 60).rounded()) : 0
        return "\(minutes) " + replacementTexts[.minutes]
    }

    private func calendarText(clock: GameClock, subtag: String) -> String? {
        let hour = clock.hourOfDay
        switch subtag {
        case "hour12":
            let whole = Int(hour) % 12
            return String(whole == 0 ? 12 : whole)
        case "minutes":
            let minutes = Int(hour * 60) % 60
            return minutes < 10 ? "0\(minutes)" : String(minutes)
        case "month": return String(clock.month)
        case "monthword": return GameClock.monthNames[clock.month - 1]
        case "day": return String(clock.day)
        case "weekday": return GameClock.weekdayNames[clock.weekday]
        case "year": return String(clock.year)
        case "timespan": return replacementTexts[TextReplacementText.span(atHour: hour)]
        case "meridiem": return hour < 12 ? "AM" : "PM"
        default: return nil
        }
    }

    private func fill(named wanted: String, in quest: Quest) -> AliasFill? {
        if let alias = quest.aliases.first(where: { $0.name?.lowercased() == wanted }) {
            return name(ofAlias: alias.id, in: quest.formID).map {
                AliasFill(name: $0, isFemale: isFemale(quest.formID, alias.id))
            }
        }
        return wanted == "player" ? player : nil
    }
}

nonisolated extension QuestAliasNaming {
    /// `text` with every tag OpenSky reads replaced.
    ///
    /// Scans rather than uses a regular expression so an unterminated `<` costs
    /// nothing: it is copied through with the rest of the sentence.
    public func substituting(_ text: String, in quest: Quest) -> String {
        guard text.contains(Self.tagOpen) else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var rest = Substring(text)
        while let open = rest.firstIndex(of: Self.tagOpen) {
            result += rest[..<open]
            rest = rest[rest.index(after: open)...]
            guard let close = rest.firstIndex(of: Self.tagClose) else {
                // Unterminated tag: put the delimiter back and stop scanning.
                result.append(Self.tagOpen)
                break
            }
            let body = rest[..<close]
            rest = rest[rest.index(after: close)...]
            switch replacement(for: body, in: quest) {
            case let .text(replacement):
                result += replacement
            case .missing where marksMissingTags:
                result += replacementTexts[.invalidTag]
            case .missing, .unread:
                result.append(Self.tagOpen)
                result += body
                result.append(Self.tagClose)
            }
        }
        result += rest
        return result
    }
}
