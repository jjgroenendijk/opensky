// `openskycli game run` scripts: one request per line, as JSON, with an
// optional `expect` object checked against the reply's result.

import Foundation

nonisolated public struct AgentScriptStep: Equatable, Sendable {
    public var lineNumber: Int
    public var request: AgentRequest
    /// Dotted result paths and the value each must hold.
    public var expect: [String: AgentJSON]

    public init(lineNumber: Int, request: AgentRequest, expect: [String: AgentJSON] = [:]) {
        self.lineNumber = lineNumber
        self.request = request
        self.expect = expect
    }
}

nonisolated public enum AgentScript {
    /// Two numbers this close count as equal, so a float round trip passes.
    public static let numberTolerance = 1e-4

    /// Blank lines and lines starting with `#` are skipped.
    public static func parse(_ text: String) throws(AgentFailure) -> [AgentScriptStep] {
        var steps: [AgentScriptStep] = []
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
        {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let number = index + 1
            let object: AgentJSON
            do {
                object = try JSONDecoder().decode(AgentJSON.self, from: Data(line.utf8))
            } catch {
                throw AgentFailure(.malformedRequest, "line \(number): not a JSON object")
            }
            guard let command = object["command"]?.stringValue else {
                throw AgentFailure(.malformedRequest, "line \(number): no command")
            }
            let args = object["args"]?.objectValue ?? [:]
            let expect = object["expect"]?.objectValue ?? [:]
            let request = AgentRequest(id: steps.count + 1, command: command, args: args)
            steps.append(AgentScriptStep(lineNumber: number, request: request, expect: expect))
        }
        return steps
    }

    /// The expectations `result` does not meet, one message each.
    public static func mismatches(
        of result: AgentJSON?,
        against expect: [String: AgentJSON]
    ) -> [String] {
        expect.keys.sorted().compactMap { path in
            let wanted = expect[path] ?? .null
            let actual = result?.value(atPath: path)
            guard let actual, matches(actual, wanted) else {
                let got = actual.map(describe) ?? "nothing"
                return "\(path): expected \(describe(wanted)), got \(got)"
            }
            return nil
        }
    }

    /// One script line for a request, so a session can be recorded and replayed.
    public static func line(for request: AgentRequest) -> String {
        var fields: [String: AgentJSON] = ["command": .string(request.command)]
        if !request.args.isEmpty {
            fields["args"] = .object(request.args)
        }
        return AgentLineCodec.text(AgentJSON.object(fields)) + "\n"
    }

    private static func matches(_ actual: AgentJSON, _ wanted: AgentJSON) -> Bool {
        if
            let lhs = actual.doubleValue, let rhs = wanted.doubleValue,
            case .number = wanted
        {
            return abs(lhs - rhs) <= numberTolerance
        }
        return actual == wanted
    }

    private static func describe(_ value: AgentJSON) -> String {
        AgentLineCodec.text(value)
    }
}
