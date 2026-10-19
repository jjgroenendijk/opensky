// `$KEY{argument}` tokens: menu scripts build text such as `"$Hits for {" + damage + "}"`.
// The key is the token with each argument emptied to `{}`, and each `{}` of the value
// takes the next argument. Rules and sources: docs/formats/translation-strings.md.

import Foundation

nonisolated public enum TranslationToken {
    /// The display text of `token`. An argument that is a `$` token is expanded
    /// first. A token whose key `lookup` does not know stays as written.
    public static func expand(_ token: String, lookup: (String) -> String?) -> String {
        guard token.first == "$" else { return token }
        if let value = lookup(token) {
            return value
        }
        guard let parsed = parse(token), let value = lookup(parsed.key) else { return token }
        return fill(value, with: parsed.arguments.map { expand($0, lookup: lookup) })
    }

    /// The key with every argument emptied, and the arguments in order. Nil when
    /// the token has no argument or its braces do not pair up.
    static func parse(_ token: String) -> (key: String, arguments: [String])? {
        var key = ""
        var arguments: [String] = []
        var argument = ""
        var depth = 0
        for character in token {
            switch character {
            case "{":
                depth += 1
                if depth == 1 {
                    key.append(character)
                    continue
                }
            case "}":
                guard depth > 0 else { return nil }
                depth -= 1
                if depth == 0 {
                    key.append(character)
                    arguments.append(argument)
                    argument = ""
                    continue
                }
            default:
                break
            }
            if depth == 0 {
                key.append(character)
            } else {
                argument.append(character)
            }
        }
        guard depth == 0, !arguments.isEmpty else { return nil }
        return (key, arguments)
    }

    /// Puts the arguments into the `{}` slots of `value` in order. A slot past
    /// the last argument stays `{}`.
    static func fill(_ value: String, with arguments: [String]) -> String {
        var result = ""
        var remaining = arguments[...]
        var rest = Substring(value)
        while let slot = rest.range(of: "{}") {
            result += rest[..<slot.lowerBound]
            result += remaining.popFirst() ?? "{}"
            rest = rest[slot.upperBound...]
        }
        return result + rest
    }
}
