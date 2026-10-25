// Turns `openskycli game` words into one protocol request, and a result into
// readable lines for `--text`. Pure, so the CLI only reads and prints.

import Foundation

nonisolated public enum AgentCommandLine {
    /// Arguments a command gets when the words leave them out.
    static let defaults: [String: [String: AgentJSON]] = [
        "state.av": ["ref": "player"]
    ]

    /// `words` start at the command, as in `state av Health --ref target`.
    public static func request(
        _ words: [String],
        id: Int = 1
    ) throws(AgentFailure) -> AgentRequest {
        let (spec, rest) = try split(words)
        var args = defaults[spec.name] ?? [:]
        var positionals = spec.positionals.map(\.key)
        var index = rest.startIndex
        while index < rest.endIndex {
            let word = rest[index]
            index += 1
            guard isOption(word) else {
                guard !positionals.isEmpty else {
                    throw AgentFailure(
                        .invalidArgument, "\(spec.name): unexpected argument '\(word)'"
                    )
                }
                args[positionals.removeFirst()] = typed(word)
                continue
            }
            let (key, value) = try option(word, of: spec)
            if let value {
                args[key] = value
                continue
            }
            guard index < rest.endIndex, !isOption(rest[index]) else {
                throw AgentFailure(.invalidArgument, "\(spec.name): \(word) needs a value")
            }
            args[key] = typed(rest[index])
            index += 1
        }
        if
            let missing = positionals.first(where: { key in
                spec.positionals.contains { $0.key == key && !$0.optional }
            })
        {
            throw AgentFailure(.invalidArgument, "\(spec.name): missing <\(missing)>")
        }
        return AgentRequest(id: id, command: spec.name, args: args)
    }

    /// One option word: a switch gives its value, a value option gives nil for the next word.
    private static func option(
        _ word: String, of spec: AgentCommandSpec
    ) throws(AgentFailure) -> (key: String, value: AgentJSON?) {
        let name = String(word.dropFirst(2))
        // `--name=value`, as the openskycli options also take it.
        if
            let equals = name.firstIndex(of: "="),
            let found = spec.option(camelCase(String(name[..<equals]))),
            case .value = found.kind
        {
            return (found.key, typed(String(name[name.index(after: equals)...])))
        }
        if let found = spec.option(camelCase(name)) {
            switch found.kind {
            case .flag, .toggle: return (found.key, true)
            case .value: return (found.key, nil)
            case .negatedFlag: break
            }
        }
        if name.hasPrefix("no-"), let found = spec.option(camelCase(String(name.dropFirst(3)))) {
            switch found.kind {
            case .negatedFlag, .toggle: return (found.key, false)
            case .flag, .value: break
            }
        }
        throw AgentFailure(
            .invalidArgument,
            "\(spec.name): unknown option \(word); see 'openskycli game help \(displayName(spec))'"
        )
    }

    private static func split(_ words: [String]) throws(AgentFailure)
        -> (AgentCommandSpec, ArraySlice<String>)
    {
        guard let first = words.first else {
            throw AgentFailure(.invalidArgument, "no game command given")
        }
        if words.count > 1, let spec = AgentCommandCatalog.spec("\(first).\(words[1])") {
            return (spec, words.dropFirst(2))
        }
        guard let spec = AgentCommandCatalog.spec(first) else {
            throw AgentFailure(
                .unknownCommand,
                "unknown game command: \(words.prefix(2).joined(separator: " ")); "
                    + "'openskycli game help' lists them"
            )
        }
        return (spec, words.dropFirst())
    }

    /// `state.av` reads as `state av` on the command line.
    static func displayName(_ spec: AgentCommandSpec) -> String {
        spec.name.replacingOccurrences(of: ".", with: " ")
    }

    /// `--name` starts an option; `-5` is a negative number, not an option.
    private static func isOption(_ word: String) -> Bool {
        word.hasPrefix("--") && word.count > 2
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
