// The app's command catalog: one way to spell each option, unknown options refused,
// help printed from it, and its entries follow the command-line conventions.

import Foundation
@testable import OpenSkyAgentControl
import Testing

struct AgentCommandCatalogTests {
    @Test func aMisspelledOptionIsRefusedInsteadOfIgnored() {
        #expect(throws: AgentFailure.self) {
            try AgentCommandLine.request(["time", "step", "10", "--second", "0.01"])
        }
        #expect(throws: AgentFailure.self) {
            try AgentCommandLine.request(["benchmark", "--overlay", "off"])
        }
    }

    @Test func switchesTakeNoValue() throws {
        #expect(try AgentCommandLine.request(["benchmark", "--no-overlay", "--windowed"]).args
            == ["overlay": false, "windowed": true])
        #expect(try AgentCommandLine.request(["debug", "skillsmenu", "--sky"])
            .args == ["sky": true])
        #expect(throws: AgentFailure.self) {
            try AgentCommandLine.request(["debug", "rest", "8", "--sleep", "on"])
        }
    }

    @Test func aMissingRequiredPositionalIsAUsageError() {
        #expect(throws: AgentFailure.self) { try AgentCommandLine.request(["state", "quest"]) }
        #expect(throws: AgentFailure.self) { try AgentCommandLine.request(["input", "hold"]) }
    }

    @Test func aPositionalIsNotAlsoAnOption() {
        #expect(throws: AgentFailure.self) {
            try AgentCommandLine.request(["state", "packages", "--ref", "player"])
        }
    }

    @Test func theRouterRefusesAnArgumentTheCommandDoesNotRead() {
        let refusal = AgentCommandCatalog.refusal(of: AgentRequest(
            command: "time.step", args: ["n": 2, "second": 0.01]
        ))
        #expect(refusal?.code == .invalidArgument)
        #expect(AgentCommandCatalog.refusal(of: AgentRequest(command: "time.step", args: ["n": 2]))
            == nil)
        #expect(AgentCommandCatalog.refusal(of: AgentRequest(command: "dance"))?.code
            == .unknownCommand)
    }

    @Test func helpListsEveryCommandAndShowsOneCommandsOptions() throws {
        let overview = try #require(AgentCommandHelp.text(for: ["help"]))
        for spec in AgentCommandCatalog.all {
            #expect(overview.contains(AgentCommandLine.displayName(spec)))
        }
        let step = try #require(AgentCommandHelp.text(for: ["time", "step", "--help"]))
        #expect(step.contains("USAGE: openskycli game time step [<n>] [--seconds <s>]"))
        #expect(AgentCommandHelp.text(for: ["benchmark", "--no-overlay"]) == nil)
        let group = try #require(AgentCommandHelp.text(for: ["help", "state"]))
        #expect(group.contains("state av") && !group.contains("time step"))
    }

    @Test func everyEntryFollowsTheConventions() {
        var names = Set<String>()
        for spec in AgentCommandCatalog.all {
            #expect(names.insert(spec.name).inserted, "\(spec.name) is listed twice")
            #expect(isCommandName(spec.name), "\(spec.name): lowercase words joined by '.'")
            #expect(isSentence(spec.summary), "\(spec.name): summary is one sentence")
            let positional = spec.positionals.map(\.key)
            let options = spec.options.map(\.key)
            #expect(Set(positional).isDisjoint(with: options), "\(spec.name): a key is both")
            #expect(Set(positional + options).count == positional.count + options.count)
            let firstOptional = spec.positionals.firstIndex(where: \.optional) ?? positional.count
            let trailingAreOptional = spec.positionals[firstOptional...].allSatisfy(\.optional)
            #expect(
                trailingAreOptional,
                "\(spec.name): a required positional follows an optional one"
            )
            for key in positional + options {
                #expect(isCamelCase(key), "\(spec.name): \(key) is camel case")
            }
            for help in spec.positionals.map(\.help) + spec.options.map(\.help) {
                #expect(isSentence(help), "\(spec.name): \(help)")
            }
        }
    }

    private func isCommandName(_ text: String) -> Bool {
        text.range(of: #"^[a-z]+(\.[a-z]+)?$"#, options: .regularExpression) != nil
    }

    private func isCamelCase(_ text: String) -> Bool {
        text.range(of: #"^[a-z][a-zA-Z0-9]*$"#, options: .regularExpression) != nil
    }

    private func isSentence(_ text: String) -> Bool {
        guard let first = text.first, first.isUppercase || first.isNumber else { return false }
        return text.hasSuffix(".") && text.count <= 80
    }
}
