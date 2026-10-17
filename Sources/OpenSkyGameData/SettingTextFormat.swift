// Fills the `%s`, `%i`, and `%d` places of a string setting, such as
// `sSkillIncreased` "%s Increased to %i", without `String(format:)`.

nonisolated public enum SettingTextFormat {
    /// Fills each place in order; a place with no argument left stays as written,
    /// and `%%` reads as one `%`. Text from a plugin never reaches `String(format:)`.
    public static func fill(_ template: String, _ arguments: [String]) -> String {
        var result = ""
        var remaining = arguments[...]
        var rest = Substring(template)
        while let percent = rest.firstIndex(of: "%") {
            result += rest[..<percent]
            let after = rest[rest.index(after: percent)...]
            switch after.first {
            case "%":
                result.append("%")
                rest = after.dropFirst()
            case "s", "i", "d":
                if let argument = remaining.popFirst() {
                    result += argument
                } else {
                    result += rest[percent...].prefix(2)
                }
                rest = after.dropFirst()
            default:
                result.append("%")
                rest = after
            }
        }
        return result + rest
    }
}
