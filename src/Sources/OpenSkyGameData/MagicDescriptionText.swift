// Fills the tags of a magic effect's description, as the magic menu shows it. The tag
// rules are the CK wiki's "Magic Item Description"; see docs/engine/magic.md#magic-menu.

nonisolated public enum MagicDescriptionText: Sendable {
    /// The values one effect fills in. A nil value is a value the effect does not have,
    /// such as the magnitude of an effect flagged No Magnitude; its tag shows nothing.
    public struct Values: Equatable, Sendable {
        public var magnitude: Float?
        public var duration: Float?
        public var area: Float?

        public init(magnitude: Float?, duration: Float?, area: Float?) {
            self.magnitude = magnitude
            self.duration = duration
            self.area = area
        }
    }

    /// `template` with each `<tag>` replaced. `<mag>`, `<dur>`, and `<area>` show the
    /// value; `<global=EditorID>` shows the global's value, or nothing when it has none.
    /// Any other tag shows its name, cut at the first `.` or `=`.
    public static func filled(
        _ template: String, values: Values, global: (String) -> Float? = { _ in nil }
    ) -> String {
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "<") {
            result += rest[..<open]
            guard let close = rest[open...].firstIndex(of: ">") else {
                result += rest[open...]
                return result
            }
            result += replacement(String(rest[rest.index(after: open) ..< close]), values, global)
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    /// A whole number shows no decimals; any other shows up to two.
    public static func number(_ value: Float) -> String {
        let hundredths = Int((value * 100).rounded())
        let sign = hundredths < 0 ? "-" : ""
        let whole = abs(hundredths) / 100
        let fraction = abs(hundredths) % 100
        guard fraction != 0 else { return "\(sign)\(whole)" }
        let digits = fraction % 10 == 0 ? "\(fraction / 10)" :
            String("\(fraction + 100)".dropFirst())
        return "\(sign)\(whole).\(digits)"
    }

    private static func replacement(
        _ tag: String, _ values: Values, _ global: (String) -> Float?
    ) -> String {
        let name = tag.prefix { $0 != "." && $0 != "=" }
        let parameter = tag.firstIndex(of: "=").map { String(tag[tag.index(after: $0)...]) }
        let value: Float?
        switch name.lowercased() {
        case "mag": value = values.magnitude
        case "dur": value = values.duration
        case "area": value = values.area
        case "global": value = parameter.flatMap(global)
        default: return String(name)
        }
        return value.map(number) ?? ""
    }
}
