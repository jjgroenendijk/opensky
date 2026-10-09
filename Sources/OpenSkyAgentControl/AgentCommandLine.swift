// Turns `openskycli game` words into one protocol request, and a result into
// readable lines for `--text`. Pure, so the CLI only reads and prints.

import Foundation

nonisolated public enum AgentCommandLine {
    /// The positional argument names of each command, after its own words.
    public static let positionals: [String: [String]] = [
        "status": [], "quit": [], "screenshot": [], "events": [],
        "input.press": ["action"], "input.release": ["action"], "input.hold": ["action"],
        "input.look": [], "input.select": ["label"], "input.text": ["text"],
        "input.point": [], "input.click": [],
        "time.pause": [], "time.resume": [], "time.step": ["n"], "time.scale": ["x"],
        "state.player": [], "state.target": [], "state.actors": [], "state.menu": [],
        "state.quest": ["id"], "state.scenes": [], "state.scripts": ["ref"],
        "state.packages": ["ref"],
        "state.av": ["name"], "state.global": ["id"],
        "state.time": [], "state.frame": [],
        "debug.teleport": [], "debug.time": ["hour"], "debug.weather": ["id"],
        "debug.av": ["name"], "debug.item": ["id"], "debug.quest": ["id", "stage"],
        "debug.kill": ["ref"], "debug.resurrect": ["ref"], "debug.overlay": ["name", "on"]
    ]

    /// Arguments a command gets when the words leave them out.
    static let defaults: [String: [String: AgentJSON]] = [
        "state.av": ["ref": "player"]
    ]

    /// `words` start at the command, as in `state av Health --ref target`.
    public static func request(
        _ words: [String],
        id: Int = 1
    ) throws(AgentFailure) -> AgentRequest {
        let (command, rest) = try split(words)
        var args = defaults[command] ?? [:]
        var names = positionals[command] ?? []
        var index = rest.startIndex
        while index < rest.endIndex {
            let word = rest[index]
            index += 1
            if word.hasPrefix("--"), word.count > 2 {
                let option = word.dropFirst(2)
                if let equals = option.firstIndex(of: "=") {
                    args[camelCase(String(option[..<equals]))] =
                        typed(String(option[option.index(after: equals)...]))
                    continue
                }
                let key = camelCase(String(option))
                if index < rest.endIndex, !isOption(rest[index]) {
                    args[key] = typed(rest[index])
                    index += 1
                } else {
                    args[key] = true
                }
                continue
            }
            guard !names.isEmpty else {
                throw AgentFailure(.invalidArgument, "\(command): unexpected argument '\(word)'")
            }
            args[names.removeFirst()] = typed(word)
        }
        return AgentRequest(id: id, command: command, args: args)
    }

    private static func split(_ words: [String]) throws(AgentFailure)
        -> (String, ArraySlice<String>)
    {
        guard let first = words.first else {
            throw AgentFailure(.invalidArgument, "no game command given")
        }
        if words.count > 1, positionals["\(first).\(words[1])"] != nil {
            return ("\(first).\(words[1])", words.dropFirst(2))
        }
        guard positionals[first] != nil else {
            throw AgentFailure(
                .unknownCommand,
                "unknown game command: \(words.prefix(2).joined(separator: " "))"
            )
        }
        return (first, words.dropFirst())
    }

    /// `--name` starts an option; `-5` is a negative number, not an option.
    private static func isOption(_ word: String) -> Bool {
        word.hasPrefix("--")
    }

    static func camelCase(_ kebab: String) -> String {
        let parts = kebab.split(separator: "-")
        guard let head = parts.first else { return kebab }
        return String(head) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
    }

    /// Words become numbers or booleans when they read as one; the rest stay text.
    static func typed(_ word: String) -> AgentJSON {
        switch word.lowercased() {
        case "true", "on": return true
        case "false", "off": return false
        default: break
        }
        if
            word.range(of: #"^-?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
            let number = Double(word)
        {
            return .number(number)
        }
        return .string(word)
    }

    /// One `path: value` line per leaf, for `--text`.
    public static func textLines(_ value: AgentJSON, prefix: String = "") -> [String] {
        switch value {
        case let .object(fields):
            return fields.keys.sorted().flatMap { key in
                textLines(fields[key] ?? .null, prefix: prefix.isEmpty ? key : "\(prefix).\(key)")
            }
        case let .array(items) where items.contains(where: \.isContainer):
            return items.enumerated().flatMap { index, item in
                textLines(item, prefix: "\(prefix)[\(index)]")
            }
        default:
            let text = scalarText(value)
            return [prefix.isEmpty ? text : "\(prefix): \(text)"]
        }
    }

    /// Whole numbers print without a fraction, so a FormID or a count reads plainly.
    private static func numberText(_ number: Double) -> String {
        guard number.rounded() == number, abs(number) < 1e15 else {
            return String(format: "%.4g", number)
        }
        return String(Int(number))
    }

    private static func scalarText(_ value: AgentJSON) -> String {
        switch value {
        case .null: "none"
        case let .bool(flag): flag ? "true" : "false"
        case let .number(number): numberText(number)
        case let .string(text): text
        case let .array(items): items.map(scalarText).joined(separator: ", ")
        case .object: "{...}"
        }
    }
}

nonisolated extension AgentJSON {
    var isContainer: Bool {
        switch self {
        case .array, .object: true
        default: false
        }
    }
}
