// `openskycli game help [command]`: help for the app's commands, printed from the
// running app's catalog, or from this build's catalog without a running app.

import Foundation

nonisolated public enum AgentCommandHelp {
    /// Help text when `words` ask for it: no words, `help ...`, or a `--help` or `-h`
    /// anywhere. Nil means the words are a command to send.
    public static func text(
        for words: [String], commands: AgentCommandList = .builtIn
    ) -> String? {
        let helpWords: Set = ["--help", "-h"]
        let asked = words.isEmpty || words.first == "help" || words
            .contains(where: helpWords.contains)
        guard asked else { return nil }
        let rest = words.filter { $0 != "help" && !helpWords.contains($0) && !$0.hasPrefix("--") }
        let name = rest.prefix(2).joined(separator: ".")
        if
            let spec = commands.spec(name) ?? rest.first.flatMap(commands.spec)
        {
            return text(spec)
        }
        let group = rest.first ?? ""
        let members = commands.specs.filter { $0.name.hasPrefix("\(group).") }
        return overview(members.isEmpty ? commands.specs : members)
    }

    static let commonOptions = "[--text] [--socket <path>] [--reply-timeout <s>] [--record <file>]"

    private static func overview(_ specs: [AgentCommandSpec]) -> String {
        let width = specs.map { AgentCommandLine.displayName($0).count }.max() ?? 0
        let rows = specs.map { spec in
            let name = AgentCommandLine.displayName(spec)
            return "  " + name.padding(toLength: width + 2, withPad: " ", startingAt: 0)
                + spec.summary
        }
        return """
        OVERVIEW: Commands the running app answers.

        USAGE: openskycli game <command> \(commonOptions)

        COMMANDS:
        \(rows.joined(separator: "\n"))

          launch, attach, and run belong to openskycli: see 'openskycli game <name> --help'.
          See 'openskycli game help <command>' for one command's options.
        """
    }

    private static func text(_ spec: AgentCommandSpec) -> String {
        let positionals = spec.positionals.map { $0.optional ? "[<\($0.key)>]" : "<\($0.key)>" }
        let options = spec.options.map { "[\(usage($0))]" }
        let usageLine = (["openskycli game", AgentCommandLine.displayName(spec)] + positionals
            + options).joined(separator: " ")
        var sections = ["OVERVIEW: \(spec.summary)", "USAGE: \(usageLine)"]
        let argumentRows = spec.positionals.map { ("<\($0.key)>", $0.help) }
        if !argumentRows.isEmpty {
            sections.append("ARGUMENTS:\n" + table(argumentRows))
        }
        let optionRows = spec.options.map { (usage($0), $0.help) }
            + [("--text", "Print path: value lines instead of JSON.")]
        sections.append("OPTIONS:\n" + table(optionRows))
        return sections.joined(separator: "\n\n")
    }

    /// `--name <value>`, `--name`, or `--no-name`, in the spelling the command line takes.
    static func usage(_ option: AgentCommandSpec.Option) -> String {
        let name = kebabCase(option.key)
        switch option.kind {
        case let .value(valueName): return "--\(name) <\(valueName)>"
        case .flag: return "--\(name)"
        case .negatedFlag: return "--no-\(name)"
        case .toggle: return "--\(name) | --no-\(name)"
        }
    }

    static func kebabCase(_ camel: String) -> String {
        camel.reduce(into: "") { result, character in
            if character.isUppercase {
                result += "-" + character.lowercased()
            } else {
                result.append(character)
            }
        }
    }

    private static func table(_ rows: [(String, String)]) -> String {
        let width = rows.map(\.0.count).max() ?? 0
        return rows.map { left, right in
            "  " + left.padding(toLength: max(width + 2, 24), withPad: " ", startingAt: 0) + right
        }.joined(separator: "\n")
    }
}
