// A call site keeps what it resolved to, and finds it again when the receiver's
// script or state differs from the one it was found for.

import Foundation
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusCallSiteTests {
    typealias Support = PapyrusTestSupport

    /// `Ask(target)` returns `target.Pick()` from one call site.
    private static let caller = PexFixture.runtimeObject(
        name: "Caller",
        states: [Support.state(functions: [("Ask", PexFixture.runtimeFunction(
            returnType: "Int",
            parameters: [PexTypedName(name: "target", typeName: "PickerBase")],
            locals: [PexTypedName(name: "result", typeName: "Int")],
            instructions: [
                PexInstruction(opcode: .callMethod, operands: [
                    .identifier("Pick"), .identifier("target"), .identifier("result"), .integer(0)
                ]),
                PexInstruction(opcode: .returnValue, operands: [.identifier("result")])
            ]
        ))])]
    )

    /// The shared parent, so `Ask` can declare its parameter with a loaded script.
    private static let base = PexFixture.runtimeObject(
        name: "PickerBase", states: [Support.state(functions: [])]
    )

    private static func picker(_ name: String, _ values: [(state: String, value: Int32)])
        -> PexObject
    {
        PexFixture.runtimeObject(
            name: name,
            parent: "PickerBase",
            states: values.map { entry in
                Support.state(entry.state, functions: [("Pick", PexFixture.runtimeFunction(
                    returnType: "Int",
                    instructions: [PexInstruction(opcode: .returnValue, operands: [
                        .integer(entry.value)
                    ])]
                ))])
            }
        )
    }

    @Test func oneCallSiteFollowsTheReceiversScriptAndState() throws {
        let first = Self.picker("FirstPicker", [("", 1), ("Other", 9)])
        let second = Self.picker("SecondPicker", [("", 5)])
        let (runtime, caller) = Support.runtime(objects: [Self.caller, Self.base, first, second])
        let one = try runtime.makeInstance(scriptName: "FirstPicker")
        let two = try runtime.makeInstance(scriptName: "SecondPicker")

        func ask(_ target: PapyrusObjectHandle) -> PapyrusValue? {
            Support.value(runtime.invoke("Ask", on: caller, arguments: [.object(target)]))
        }

        #expect(ask(one) == .integer(1))
        #expect(ask(one) == .integer(1))
        #expect(ask(two) == .integer(5))
        runtime.instances[one]?.activeState = "Other"
        #expect(ask(one) == .integer(9))
        runtime.instances[one]?.activeState = ""
        #expect(ask(one) == .integer(1))
    }

    @Test func aNoneReceiverStillReturnsTheDefaultAfterARealCall() throws {
        let first = Self.picker("FirstPicker", [("", 1)])
        let (runtime, caller) = Support.runtime(objects: [Self.caller, Self.base, first])
        let one = try runtime.makeInstance(scriptName: "FirstPicker")

        #expect(Support.value(runtime.invoke("Ask", on: caller, arguments: [.object(one)]))
            == .integer(1))
        #expect(Support.value(runtime.invoke("Ask", on: caller, arguments: [.none]))
            == .integer(0))
        #expect(runtime.tally.noneReceiverTotal == 1)
    }
}
