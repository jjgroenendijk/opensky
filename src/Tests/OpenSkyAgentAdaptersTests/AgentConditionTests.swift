// `state condition` runs one function from the live condition context on a reference,
// and answers its value or why it has none.

import Foundation
import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkySessionTesting
import Testing

@MainActor
struct AgentConditionTests {
    private let host = AgentHost()
    private let world: AgentWorldAdapter

    init() {
        var functions = ConditionFunctionRegistry()
        functions.register(ConditionFunction(index: 5, name: "GetLocked") { call in
            call.context.subject == .player ? .success(1) : .success(0)
        })
        functions.register(ConditionFunction(
            index: 67, name: "GetInCell", parameter1: .formID
        ) { call in
            .success(Float(call.parameter1?.asFormID.rawValue ?? 0))
        })
        functions.register(ConditionFunction(index: 35, name: "GetDisabled") { _ in
            .failure(.unknownFunction(35))
        })
        host.fakeRuntimeState.conditionContextResult = ConditionContext(functions: functions)
        world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    private func answer(_ function: String, param: String? = nil) throws -> [String: AgentJSON] {
        let query = AgentStateQuery.condition(
            function: function, reference: "player", parameter: param
        )
        guard case let .object(fields) = try world.query(query) else {
            Issue.record("no object")
            return [:]
        }
        return fields
    }

    @Test func aFunctionRunsOnTheReferenceByItsNameInAnyCase() throws {
        let fields = try answer("getlocked")
        #expect(fields["function"] == .string("GetLocked"))
        #expect(fields["value"] == .init(Float(1)))
        #expect(fields["failure"] == .null)
        #expect(host.fakeRuntimeState.conditionContextCalls == [[.player]])
    }

    @Test func aFormParameterIsReadAsHex() throws {
        #expect(try answer("GetInCell", param: "1A")["value"] == .init(Float(0x1A)))
        #expect(throws: AgentFailure.self) { try answer("GetInCell", param: "cell") }
    }

    @Test func aFailureIsNamedAndAnUnknownNameRefused() throws {
        #expect(try answer("GetDisabled")["failure"] != .null)
        #expect(throws: AgentFailure.self) { try answer("NoSuchFunction") }
    }

    @Test func aNumberParameterIsWhole() throws {
        #expect(try answer("GetLocked", param: "-2")["value"] == .init(Float(1)))
        #expect(throws: AgentFailure.self) { try answer("GetLocked", param: "1.5") }
    }
}
