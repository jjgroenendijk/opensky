import Foundation
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

/// The `CW` quest carries `CWHoldManagerScript` and `CWScript`. Its handle maps to the
/// first one, yet `CW.CWSiegeCity` through a `CWScript` variable reads the second.
@MainActor
struct PapyrusSiblingMemberTests {
    typealias Support = PapyrusTestSupport

    @Test("a member used through a typed variable reaches the sibling script of that type")
    func aTypedMemberReachesItsSibling() throws {
        let runtime = PapyrusRuntime(files: [PexFixture.runtimeFile(objects: [
            Self.cwScript, Self.holdManager, Self.caller
        ])])
        let hold = try runtime.makeInstance(scriptName: "CWHoldManagerScript")
        let cw = try runtime.makeInstance(scriptName: "CWScript")
        runtime.siblingInstance = { handle, type in
            handle == hold && type.lowercased() == "cwscript" ? cw : nil
        }
        let caller = try runtime.makeInstance(
            scriptName: "CallerScript", initialValues: ["cw": .object(hold)]
        )
        #expect(Support.value(runtime.invoke("ReadCity", on: caller)) == .integer(7))
        #expect(Support.value(runtime.invoke("CallCount", on: caller)) == .integer(3))
    }

    private static let cwScript = PexFixture.runtimeObject(
        name: "CWScript",
        properties: [PexProperty(
            name: "CWSiegeCity",
            typeName: "Int",
            documentation: "",
            userFlags: 0,
            flags: [.readable],
            automaticVariableName: nil,
            readHandler: returning(7),
            writeHandler: nil
        )],
        states: [Support.state(functions: [("SiegeCount", returning(3))])]
    )

    private static let holdManager = PexFixture.runtimeObject(
        name: "CWHoldManagerScript", states: []
    )

    private static let caller = PexFixture.runtimeObject(
        name: "CallerScript",
        variables: [PexVariable(
            name: "cw",
            typeName: "CWScript",
            userFlags: 0,
            initialValue: .null
        )],
        states: [Support.state(functions: [
            ("ReadCity", member(.propertyGet, .identifier("CWSiegeCity"), .identifier("cw"))),
            ("CallCount", member(
                .callMethod, .identifier("SiegeCount"), .identifier("cw"), extra: [.integer(0)]
            ))
        ])]
    )

    private static func returning(_ value: Int32) -> PexFunction {
        PexFixture.runtimeFunction(
            returnType: "Int", instructions: [PexInstruction(
                opcode: .returnValue,
                operands: [.integer(value)]
            )]
        )
    }

    private static func member(
        _ opcode: PexOpcode, _ name: PexValue, _ receiver: PexValue, extra: [PexValue] = []
    ) -> PexFunction {
        PexFixture.runtimeFunction(
            returnType: "Int",
            locals: [PexTypedName(name: "result", typeName: "Int")],
            instructions: [
                PexInstruction(
                    opcode: opcode,
                    operands: [name, receiver, .identifier("result")] + extra
                ),
                PexInstruction(opcode: .returnValue, operands: [.identifier("result")])
            ]
        )
    }
}
