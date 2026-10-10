// A script whose VMAD value reaches a variable only through a property setter.

import Foundation
@testable import OpenSkyFormatsPEX
@testable import OpenSkyFormatsTesting

extension PapyrusWorldFixture {
    /// Script with a full property `Limit` whose setter copies the value into the
    /// plain variable `limitStore`, and a full property `ReadOnly` with no setter.
    public static func setterScript(_ name: String) -> PexObject {
        let setter = PexFixture.runtimeFunction(
            returnType: "None",
            parameters: [PexTypedName(name: "aiValue", typeName: "Int")],
            instructions: [
                PexInstruction(
                    opcode: .assign,
                    operands: [.identifier("limitStore"), .identifier("aiValue")]
                ),
                PexInstruction(opcode: .returnValue, operands: [.null])
            ]
        )
        let properties = [("Limit", setter), ("ReadOnly", nil)].map { name, handler in
            PexProperty(
                name: name, typeName: "Int", documentation: "", userFlags: 0,
                flags: handler == nil ? [.readable] : [.readable, .writable],
                automaticVariableName: nil, readHandler: nil, writeHandler: handler
            )
        }
        return PexFixture.runtimeObject(
            name: name,
            variables: [PexVariable(
                name: "limitStore", typeName: "Int", userFlags: 0, initialValue: .integer(0)
            )],
            properties: properties,
            states: []
        )
    }
}
