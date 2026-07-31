// `GlobalVariable` natives over a synthetic `GlobalStore` (issue #172): the
// script write goes through the GLOB coercion seam, so a short or long global
// never holds a fraction.
//
// Fixtures are built in code — never extracted game files (AGENTS.md "Legal &
// IP boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusNativeGlobalVariableTests {
    private static let shortID = FormID(0x0000_0201)
    private static let longID = FormID(0x0000_0202)
    private static let floatID = FormID(0x0000_0203)
    private static let undefinedID = FormID(0x0000_0299)

    private struct Fixture {
        let session: PapyrusWorldFixture.Session
        let registry: PapyrusNativeRegistry
    }

    private static func globalStore() -> GlobalStore {
        GlobalStore(
            globals: [
                Global(
                    formID: shortID,
                    editorID: "OpenSkyProbeShort",
                    value: GlobalValue(type: .short, rawValue: 1)
                ),
                Global(
                    formID: longID,
                    editorID: "OpenSkyProbeLong",
                    value: GlobalValue(type: .long, rawValue: 100),
                    isConstant: true
                ),
                Global(
                    formID: floatID,
                    editorID: "OpenSkyProbeFloat",
                    value: GlobalValue(type: .float, rawValue: 0.5)
                )
            ],
            resolver: PapyrusWorldFixture.resolver
        )
    }

    private func fixture() throws -> Fixture {
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: 0x0000_0AAA,
            scripts: [VMADFixture.Script("Lever", properties: [])]
        )
        let session = PapyrusWorldFixture.session(
            objects: [PapyrusWorldFixture.eventScript("Lever", events: [])],
            entries: [entry],
            globals: Self.globalStore()
        )
        PapyrusWorldFixture.drain(session.world)
        return Fixture(
            session: session,
            registry: PapyrusWorldFixture.registry(for: session)
        )
    }

    /// The handle a `GlobalVariable` property would bind to: world identity for
    /// the GLOB, then the session-stable opaque handle for that identity.
    private func handle(_ fixture: Fixture, _ formID: FormID) throws -> PapyrusObjectHandle {
        let key = try #require(ReferenceKey.resolve(
            formID, using: PapyrusWorldFixture.resolver
        ))
        return fixture.session.world.objectHandle(for: key)
    }

    private func call(
        _ functionName: String,
        _ fixture: Fixture,
        receiver: PapyrusObjectHandle?,
        arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "GlobalVariable",
            functionName,
            receiver: receiver,
            arguments: arguments,
            returnType: returnType
        ))
    }

    @Test func getValueReadsThePluginDefaultUntilAScriptWritesOne() throws {
        let fixture = try fixture()
        let floatHandle = try handle(fixture, Self.floatID)
        #expect(call(
            "GetValue", fixture, receiver: floatHandle, returnType: .float
        ) == .returned(.float(0.5)))

        #expect(call(
            "SetValue", fixture, receiver: floatHandle, arguments: [.float(2.25)]
        ) == .returned(.none))
        #expect(call(
            "GetValue", fixture, receiver: floatHandle, returnType: .float
        ) == .returned(.float(2.25)))
        #expect(fixture.session.worldState.overriddenGlobalCount == 1)
    }

    /// A short or long global rounds on write, half away from zero, because
    /// `WorldStateStore.setGlobal(_:formID:defaults:)` applies
    /// `Global.ValueType.coerce`. A float global keeps its fraction.
    @Test func setValueCoercesShortAndLongButNotFloat() throws {
        let fixture = try fixture()
        let shortHandle = try handle(fixture, Self.shortID)
        let longHandle = try handle(fixture, Self.longID)
        let floatHandle = try handle(fixture, Self.floatID)

        #expect(call(
            "SetValue", fixture, receiver: shortHandle, arguments: [.float(3.7)]
        ) == .returned(.none))
        #expect(call(
            "GetValue", fixture, receiver: shortHandle, returnType: .float
        ) == .returned(.float(4)))

        #expect(call(
            "SetValue", fixture, receiver: longHandle, arguments: [.float(-2.5)]
        ) == .returned(.none))
        #expect(call(
            "GetValue", fixture, receiver: longHandle, returnType: .float
        ) == .returned(.float(-3)))

        #expect(call(
            "SetValue", fixture, receiver: floatHandle, arguments: [.float(3.7)]
        ) == .returned(.none))
        #expect(call(
            "GetValue", fixture, receiver: floatHandle, returnType: .float
        ) == .returned(.float(3.7)))
    }

    /// `Global.isConstant` is decoded and deliberately not enforced: the
    /// Creation Kit's rule is about editing authored data, and no open
    /// documentation says the engine refuses a scripted write. The long global
    /// in this fixture is constant and the write lands.
    @Test func setValueDoesNotRefuseAConstantGlobal() throws {
        let fixture = try fixture()
        let longHandle = try handle(fixture, Self.longID)
        #expect(call(
            "SetValue", fixture, receiver: longHandle, arguments: [.float(7)]
        ) == .returned(.none))
        #expect(call(
            "GetValue", fixture, receiver: longHandle, returnType: .float
        ) == .returned(.float(7)))
    }

    @Test func integerAccessorsTruncateTowardZero() throws {
        let fixture = try fixture()
        let floatHandle = try handle(fixture, Self.floatID)
        let shortHandle = try handle(fixture, Self.shortID)

        #expect(call(
            "SetValueInt", fixture, receiver: shortHandle, arguments: [.integer(-9)]
        ) == .returned(.none))
        #expect(call(
            "GetValueInt", fixture, receiver: shortHandle, returnType: .integer
        ) == .returned(.integer(-9)))

        #expect(call(
            "SetValue", fixture, receiver: floatHandle, arguments: [.float(-1.9)]
        ) == .returned(.none))
        #expect(call(
            "GetValueInt", fixture, receiver: floatHandle, returnType: .integer
        ) == .returned(.integer(-1)))
    }

    @Test func readingAGlobalThisSessionDoesNotDefineFails() throws {
        let fixture = try fixture()
        let unknown = try handle(fixture, Self.undefinedID)
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "GetValue", fixture, receiver: unknown, returnType: .float
        )))
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "GetValueInt", fixture, receiver: unknown, returnType: .integer
        )))
    }

    @Test func malformedWritesFailAndStoreNothing() throws {
        let fixture = try fixture()
        let shortHandle = try handle(fixture, Self.shortID)
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "SetValue", fixture, receiver: shortHandle, arguments: [.string("2")]
        )))
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "SetValue", fixture, receiver: shortHandle, arguments: [.float(.infinity)]
        )))
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "SetValueInt", fixture, receiver: shortHandle, arguments: [.float(2)]
        )))
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "SetValue", fixture, receiver: shortHandle
        )))
        #expect(fixture.session.worldState.overriddenGlobalCount == 0)
    }

    @Test func headlessCallsFailInsteadOfGuessing() {
        let registry = PapyrusNativeRegistry.standard
        let receiver = PapyrusObjectHandle(7)
        for functionName in ["GetValue", "GetValueInt", "SetValue", "SetValueInt"] {
            let result = registry.invoke(PapyrusWorldFixture.methodCall(
                "GlobalVariable",
                functionName,
                receiver: receiver,
                arguments: [.float(1)]
            ))
            #expect(
                PapyrusWorldFixture.isInvalidArguments(result),
                "\(functionName) should fail headlessly, got \(result)"
            )
        }
    }
}
