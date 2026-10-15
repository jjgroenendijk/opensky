// The natives answered by their condition twin: the receiver runs the condition, and an
// object argument reaches it as a load-order FormID that resolves back to the same form.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeConditionTwinTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    /// `GetSitting` reads the furniture use, and `WornHasKeyword` answers 1 when its
    /// parameter names the fixture's door.
    private static func registry(door: ReferenceKey) -> ConditionFunctionRegistry {
        var registry = ConditionFunctionRegistry()
        registry.register(ConditionFunction(index: 159, name: "GetSitting") { call in
            call.referenceKey().map { _ in 3 }
        })
        registry.register(ConditionFunction(index: 633, name: "GetFlyingState") { call in
            call.referenceKey().map { _ in 0 }
        })
        registry.register(ConditionFunction(
            index: 682, name: "WornHasKeyword", parameter1: .formID
        ) { call in
            .success(ConditionFunctions.parameterKey(call, call.parameter1) == door ? 1 : 0)
        })
        return registry
    }

    private static func fixture() throws -> Fixture {
        let fixture = try Fixture.make()
        let registry = registry(door: Fixture.key(Fixture.doorID))
        fixture.session.bridge.formIDResolver = FormIDResolver(
            pluginName: PapyrusWorldFixture.pluginName, masters: []
        )
        fixture.session.bridge.conditionEvaluator = {
            ConditionEvaluator(context: ConditionContext(), registry: registry)
        }
        return fixture
    }

    private static func call(
        _ fixture: Fixture, _ name: String, _ arguments: [PapyrusValue] = [],
        returnType: PapyrusType
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Actor", name, receiver: fixture.receiver, arguments: arguments,
            returnType: returnType
        ))
    }

    @Test func aTwinReturnsTheConditionValueInTheNativeType() throws {
        let fixture = try Self.fixture()
        #expect(Self.call(fixture, "GetSitState", returnType: .integer)
            == .returned(.integer(3)))
        #expect(Self.call(fixture, "GetFlyingState", returnType: .integer)
            == .returned(.integer(0)))
    }

    @Test func anObjectArgumentReachesTheConditionAsItsForm() throws {
        let fixture = try Self.fixture()
        let door = fixture.handle(Fixture.doorID)
        #expect(Self.call(fixture, "WornHasKeyword", [.object(door)], returnType: .boolean)
            == .returned(.boolean(true)))
        #expect(Self.call(
            fixture,
            "WornHasKeyword",
            [.object(fixture.receiver)],
            returnType: .boolean
        ) == .returned(.boolean(false)))
    }

    @Test func aConditionWithNoAnswerFailsTheNative() throws {
        let fixture = try Self.fixture()
        let result = Self.call(fixture, "IsOnMount", returnType: .boolean)
        guard case .failed = result else {
            Issue.record("IsOnMount with no IsRidingMount function should fail: \(result)")
            return
        }
        fixture.session.bridge.conditionEvaluator = nil
        guard case .failed = Self.call(fixture, "GetSitState", returnType: .integer) else {
            Issue.record("GetSitState with no condition context should fail")
            return
        }
    }
}
