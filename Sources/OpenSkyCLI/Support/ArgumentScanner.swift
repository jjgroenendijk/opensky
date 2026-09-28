// Tiny option scanner for openskycli: positional arguments plus --name value
// options, order-insensitive for options. Stdlib suffices for this surface
// (AGENTS.md: prefer stdlib when it does the job) — swift-argument-parser
// stays out until the command set outgrows this (docs/tools/cli.md).

import Foundation

struct ArgumentScanner {
    private var remaining: [String]

    init(_ arguments: [String]) {
        remaining = arguments
    }

    /// Consumes `--name value` from anywhere in the remaining arguments.
    mutating func option(_ name: String) throws -> String? {
        guard let index = remaining.firstIndex(of: name) else { return nil }
        guard index + 1 < remaining.count else {
            throw CLIError.usage("\(name) needs a value")
        }
        let value = remaining[index + 1]
        remaining.removeSubrange(index ... index + 1)
        return value
    }

    /// `option` that must be present.
    mutating func requiredOption(_ name: String) throws -> String {
        guard let value = try option(name) else {
            throw CLIError.usage("missing required \(name) <value>")
        }
        return value
    }

    /// Consumes a bare `--name` switch.
    mutating func flag(_ name: String) -> Bool {
        guard let index = remaining.firstIndex(of: name) else { return false }
        remaining.remove(at: index)
        return true
    }

    /// Consumes the next positional argument; consume options first.
    mutating func positional(_ label: String) throws -> String {
        guard let value = next() else {
            throw CLIError.usage("missing <\(label)> argument")
        }
        return value
    }

    mutating func next() -> String? {
        guard !remaining.isEmpty else { return nil }
        return remaining.removeFirst()
    }

    /// Leftover arguments are user error — fail loud instead of ignoring.
    func finish() throws {
        guard remaining.isEmpty else {
            throw CLIError.usage("unexpected arguments: \(remaining.joined(separator: " "))")
        }
    }
}
