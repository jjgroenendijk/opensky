import Foundation
@testable import opensky
import Testing

struct PapyrusObjectOpcodeTests {
    typealias Support = PapyrusTestSupport

    @Test func methodParentAndStaticCallsUseExplicitFrames() {
        let (runtime, handle) = Support.runtime(objects: callObjects())
        #expect(Support.value(runtime.invoke("Run", on: handle)) == .integer(24))
        #expect(runtime.tally.opcodeCounts[.callMethod] == 1)
        #expect(runtime.tally.opcodeCounts[.callParent] == 1)
        #expect(runtime.tally.opcodeCounts[.callStatic] == 1)
    }

    @Test func automaticPropertyGetAndSet() {
        let backing = PexVariable(
            name: "::value_var",
            typeName: "Int",
            userFlags: 0,
            initialValue: .integer(1)
        )
        let property = PexProperty(
            name: "Value",
            typeName: "Int",
            documentation: "",
            userFlags: 0,
            flags: [.readable, .writable, .automatic],
            automaticVariableName: "::value_var",
            readHandler: nil,
            writeHandler: nil
        )
        let script = object(
            "PropertyScript",
            variables: [backing],
            properties: [property],
            states: [Support.state(functions: [("Run", propertyRunFunction())])]
        )
        let (runtime, handle) = Support.runtime(objects: [script])
        #expect(Support.value(runtime.invoke("Run", on: handle)) == .integer(12))
    }

    @Test func arrayCreateLengthGetSetFindAndReverseFind() {
        let script = object(
            "ArrayScript",
            states: [Support.state(functions: [("Run", arrayRunFunction())])]
        )
        let (runtime, handle) = Support.runtime(objects: [script])
        #expect(Support.value(runtime.invoke("Run", on: handle)) == .integer(10))
        for opcode in [
            PexOpcode.arrayCreate, .arrayLength, .arrayGetElement, .arraySetElement,
            .arrayFindElement, .arrayReverseFindElement
        ] {
            #expect(runtime.tally.opcodeCounts[opcode] != nil)
        }
    }

    private func callObjects() -> [PexObject] {
        let parentValue = function(
            returnType: "Int",
            instructions: [op(.returnValue, .integer(8))]
        )
        let staticValue = function(
            returnType: "Int",
            flags: [.global],
            instructions: [op(.returnValue, .integer(9))]
        )
        let echo = function(
            returnType: "Int",
            parameters: [typed("value", "Int")],
            instructions: [op(.returnValue, .identifier("value"))]
        )
        let parent = object(
            "Parent",
            states: [Support.state(functions: [("ParentValue", parentValue)])]
        )
        let utility = object(
            "Utility",
            states: [Support.state(functions: [("StaticValue", staticValue)])]
        )
        let child = object(
            "Child",
            parent: "Parent",
            states: [Support.state(functions: [("Run", callRunFunction()), ("Echo", echo)])]
        )
        return [child, parent, utility]
    }

    private func callRunFunction() -> PexFunction {
        function(
            returnType: "Int",
            locals: [
                typed("methodResult", "Int"),
                typed("parentResult", "Int"),
                typed("staticResult", "Int"),
                typed("result", "Int")
            ],
            instructions: [
                op(
                    .callMethod,
                    .identifier("Echo"),
                    .identifier("self"),
                    .identifier("methodResult"),
                    .integer(1),
                    .integer(7)
                ),
                op(
                    .callParent,
                    .identifier("ParentValue"),
                    .identifier("parentResult"),
                    .integer(0)
                ),
                op(
                    .callStatic,
                    .identifier("Utility"),
                    .identifier("StaticValue"),
                    .identifier("staticResult"),
                    .integer(0)
                ),
                op(
                    .integerAdd,
                    .identifier("result"),
                    .identifier("methodResult"),
                    .identifier("parentResult")
                ),
                op(
                    .integerAdd,
                    .identifier("result"),
                    .identifier("result"),
                    .identifier("staticResult")
                ),
                op(.returnValue, .identifier("result"))
            ]
        )
    }

    private func propertyRunFunction() -> PexFunction {
        function(
            returnType: "Int",
            locals: [typed("result", "Int")],
            instructions: [
                op(.propertySet, .identifier("Value"), .identifier("self"), .integer(12)),
                op(
                    .propertyGet,
                    .identifier("Value"),
                    .identifier("self"),
                    .identifier("result")
                ),
                op(.returnValue, .identifier("result"))
            ]
        )
    }

    private func arrayRunFunction() -> PexFunction {
        function(
            returnType: "Int",
            locals: [
                typed("values", "Int[]"),
                typed("length", "Int"),
                typed("element", "Int"),
                typed("first", "Int"),
                typed("last", "Int"),
                typed("result", "Int")
            ],
            instructions: arraySetupInstructions() + arrayResultInstructions()
        )
    }

    private func arraySetupInstructions() -> [PexInstruction] {
        [
            op(.arrayCreate, .identifier("values"), .integer(3)),
            op(.arraySetElement, .identifier("values"), .integer(0), .integer(4)),
            op(.arraySetElement, .identifier("values"), .integer(1), .integer(7)),
            op(.arraySetElement, .identifier("values"), .integer(2), .integer(7)),
            op(.arrayLength, .identifier("length"), .identifier("values")),
            op(
                .arrayGetElement,
                .identifier("element"),
                .identifier("values"),
                .integer(0)
            ),
            op(
                .arrayFindElement,
                .identifier("first"),
                .identifier("values"),
                .integer(7),
                .integer(0)
            ),
            op(
                .arrayReverseFindElement,
                .identifier("last"),
                .identifier("values"),
                .integer(7),
                .integer(-1)
            )
        ]
    }

    private func arrayResultInstructions() -> [PexInstruction] {
        [
            op(
                .integerAdd,
                .identifier("result"),
                .identifier("length"),
                .identifier("element")
            ),
            op(
                .integerAdd,
                .identifier("result"),
                .identifier("result"),
                .identifier("first")
            ),
            op(
                .integerAdd,
                .identifier("result"),
                .identifier("result"),
                .identifier("last")
            ),
            op(.returnValue, .identifier("result"))
        ]
    }

    private func function(
        returnType: String,
        flags: PexFunctionFlags = [],
        parameters: [PexTypedName] = [],
        locals: [PexTypedName] = [],
        instructions: [PexInstruction]
    ) -> PexFunction {
        PexFixture.runtimeFunction(
            returnType: returnType,
            flags: flags,
            parameters: parameters,
            locals: locals,
            instructions: instructions
        )
    }

    private func object(
        _ name: String,
        parent: String = "",
        variables: [PexVariable] = [],
        properties: [PexProperty] = [],
        states: [PexState]
    ) -> PexObject {
        PexFixture.runtimeObject(
            name: name,
            parent: parent,
            variables: variables,
            properties: properties,
            states: states
        )
    }

    private func typed(_ name: String, _ type: String) -> PexTypedName {
        PexTypedName(name: name, typeName: type)
    }

    private func op(_ opcode: PexOpcode, _ operands: PexValue...) -> PexInstruction {
        PexInstruction(opcode: opcode, operands: operands)
    }
}
