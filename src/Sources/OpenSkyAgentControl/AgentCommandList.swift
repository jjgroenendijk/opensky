// A set of commands the command line parses against. The app sends its own with the
// `catalog` command, so an openskycli from another build parses what that app answers.

import Foundation

nonisolated public struct AgentCommandList: Sendable {
    public let specs: [AgentCommandSpec]
    private let byName: [String: AgentCommandSpec]

    public init(_ specs: [AgentCommandSpec]) {
        self.specs = specs
        byName = Dictionary(specs.map { ($0.name, $0) }) { first, _ in first }
    }

    /// The commands this build of the app answers.
    public static let builtIn = Self(AgentCommandCatalog.all)

    public func spec(_ name: String) -> AgentCommandSpec? {
        byName[name]
    }

    /// The reply of the `catalog` command.
    public var json: AgentJSON {
        ["commands": .array(specs.map(\.json))]
    }

    /// Nil when `json` is not a catalog reply. A command it cannot read is left out.
    public init?(json: AgentJSON) {
        guard let commands = json["commands"]?.arrayValue else { return nil }
        self.init(commands.compactMap(AgentCommandSpec.init(json:)))
    }
}

nonisolated extension AgentCommandSpec {
    var json: AgentJSON {
        [
            "name": .string(name), "summary": .string(summary),
            "positionals": .array(positionals.map { positional in
                [
                    "key": .string(positional.key), "optional": .bool(positional.optional),
                    "help": .string(positional.help)
                ]
            }),
            "options": .array(options.map(\.json))
        ]
    }

    init?(json: AgentJSON) {
        guard
            let name = json["name"]?.stringValue,
            let positionals = json["positionals"]?.arrayValue,
            let options = json["options"]?.arrayValue
        else { return nil }
        self.init(
            name: name,
            summary: json["summary"]?.stringValue ?? "",
            positionals: positionals.compactMap { item in
                item["key"]?.stringValue.map { key in
                    Positional(
                        key: key, optional: item["optional"]?.boolValue ?? false,
                        help: item["help"]?.stringValue ?? ""
                    )
                }
            },
            options: options.compactMap(Option.init(json:))
        )
    }
}

nonisolated extension AgentCommandSpec.Option {
    var json: AgentJSON {
        var fields: [String: AgentJSON] = ["key": .string(key), "help": .string(help)]
        switch kind {
        case let .value(valueName):
            fields["kind"] = "value"
            fields["value"] = .string(valueName)
        case .flag: fields["kind"] = "flag"
        case .negatedFlag: fields["kind"] = "negatedFlag"
        case .toggle: fields["kind"] = "toggle"
        }
        return .object(fields)
    }

    init?(json: AgentJSON) {
        guard let key = json["key"]?.stringValue else { return nil }
        let kind: AgentCommandSpec.OptionKind
        switch json["kind"]?.stringValue {
        case "value": kind = .value(json["value"]?.stringValue ?? "value")
        case "flag": kind = .flag
        case "negatedFlag": kind = .negatedFlag
        case "toggle": kind = .toggle
        default: return nil
        }
        self.init(key: key, kind: kind, help: json["help"]?.stringValue ?? "")
    }
}
