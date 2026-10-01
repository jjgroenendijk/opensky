import FormatsPEXTesting
import Foundation
@testable import OpenSkyFormatsPEX
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

/// A `.pex` file is external input, so a repeated variable name must not trap.
@MainActor
struct PapyrusRuntimeDuplicateNameTests {
    typealias Support = PapyrusTestSupport

    @Test(arguments: ["::count_var", "::Count_var"])
    func repeatedVariableNameKeepsTheFirstDeclaration(_ secondName: String) throws {
        let script = PexFixture.runtimeObject(
            name: "DuplicateScript",
            variables: [
                Self.variable("::count_var", 1),
                Self.variable(secondName, 2)
            ],
            states: [Support.state(functions: [("Read", Self.readCount)])]
        )
        let runtime = PapyrusRuntime(files: [PexFixture.runtimeFile(objects: [script])])
        let handle = try runtime.makeInstance(scriptName: script.name)
        #expect(Support.value(runtime.invoke("Read", on: handle)) == .integer(1))
        #expect(runtime.tally.duplicateVariableTotal == 1)
    }

    private static let readCount = PexFixture.runtimeFunction(
        returnType: "Int",
        instructions: [
            PexInstruction(opcode: .returnValue, operands: [.identifier("::count_var")])
        ]
    )

    private static func variable(_ name: String, _ value: Int32) -> PexVariable {
        PexVariable(name: name, typeName: "Int", userFlags: 0, initialValue: .integer(value))
    }
}
