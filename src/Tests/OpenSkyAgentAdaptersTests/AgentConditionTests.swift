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
        functions.register(ConditionFunction(
            index: 584, name: "GetRelativeAngle", parameter1: .formID, parameter2: .integer
        ) { call in
            guard call.context.target == .player else { return .failure(.unresolvedParameter(584)) }
            return .success(Float(call.parameter2?.asInt32 ?? 0))
        })
        functions.register(ConditionFunction(index: 35, name: "GetDisabled") { _ in
            .failure(.unknownFunction(35))
        })
        host.fakeRuntimeState.conditionContextResult = ConditionContext(functions: functions)
        world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    private func answer(
        _ function: String, param: String? = nil, param2: String? = nil, target: String? = nil
    ) throws -> [String: AgentJSON] {
        let query = AgentStateQuery.condition(AgentConditionProbe(
            function: function, parameter: param, parameter2: param2, target: target
        ))
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

    @Test func theSecondParameterAndTheOtherReferenceReachTheFunction() throws {
        let fields = try answer("GetRelativeAngle", param2: "90", target: "player")
        #expect(fields["value"] == .init(Float(90)))
        #expect(host.fakeRuntimeState.conditionContextCalls == [[.player, .player]])
        #expect(throws: AgentFailure.self) { try answer("GetRelativeAngle", param2: "Z") }
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
