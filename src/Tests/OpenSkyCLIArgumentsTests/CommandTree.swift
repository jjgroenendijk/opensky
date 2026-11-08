// The `openskycli` command tree as swift-argument-parser describes it in its help dump,
// flattened to one entry per command.

import ArgumentParser
import Foundation
import OpenSkyCLIArguments

enum CommandTree {
    struct Command {
        let path: String
        let info: CommandInfo
        /// The command's own arguments, without the parser's built-in `--help`.
        var arguments: [ArgumentInfo] {
            (info.arguments ?? []).filter { !$0.longNames.contains("help") }
        }

        var options: [ArgumentInfo] {
            arguments.filter { $0.kind != "positional" }
        }
    }

    /// The fields of the dump's `CommandInfoV0` these checks read.
    struct CommandInfo: Decodable {
        let commandName: String
        let abstract: String?
        let aliases: [String]?
        let shouldDisplay: Bool
        let subcommands: [CommandInfo]?
        let arguments: [ArgumentInfo]?
    }

    /// The fields of the dump's `ArgumentInfoV0` these checks read.
    struct ArgumentInfo: Decodable {
        struct Name: Decodable {
            let kind: String
            let name: String
        }

        let kind: String
        let shouldDisplay: Bool
        let names: [Name]?
        let valueName: String?
        let abstract: String?
        let parsingStrategy: String

        var longNames: [String] {
            (names ?? []).filter { $0.kind == "long" }.map(\.name)
        }

        var shortNames: [String] {
            (names ?? []).filter { $0.kind == "short" }.map(\.name)
        }

        var displayName: String {
            longNames.first.map { "--\($0)" } ?? "<\(valueName ?? "value")>"
        }
    }

    private struct Dump: Decodable {
        let command: CommandInfo
    }

    /// Every command below the root, with its space-separated path. Built-in `help` is left out.
    static func load() -> [Command] {
        guard
            let data = OpenSkyCommandLine._dumpHelp().data(using: .utf8),
            let dump = try? JSONDecoder().decode(Dump.self, from: data)
        else { return [] }
        var commands: [Command] = []
        func walk(_ info: CommandInfo, prefix: String) {
            for child in info.subcommands ?? [] where child.commandName != "help" {
                let path = prefix.isEmpty ? child.commandName : "\(prefix) \(child.commandName)"
                commands.append(Command(path: path, info: child))
                walk(child, prefix: path)
            }
        }
        walk(dump.command, prefix: "")
        return commands
    }
}
