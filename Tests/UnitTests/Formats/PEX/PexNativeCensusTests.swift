// Typed native call resolution over synthetic PEX models.

import Foundation
@testable import opensky
import Testing

struct PexNativeCensusTests {
    @Test func resolvesStaticSelfLocalParentAndPropertyReceivers() {
        let native = PexFixture.runtimeFunction(
            returnType: "None",
            flags: .native,
            instructions: []
        )
        let base = object(
            "NativeBase",
            functions: [("Touch", native)]
        )
        let utility = object(
            "Utility",
            functions: [("Wait", native)]
        )
        let caller = callerObject()
        let census = PexNativeCensus(
            files: [PexFixture.runtimeFile(objects: [base, utility, caller])]
        )

        #expect(census.declarationTotal == 2)
        #expect(census.distinctReferencedTotal == 2)
        #expect(census.referenceTotal == 5)
        #expect(census.rankedReferences.contains {
            $0.name == "NativeBase.Touch" && $0.count == 4
        })
        #expect(census.rankedReferences.contains {
            $0.name == "Utility.Wait" && $0.count == 1
        })
    }

    @Test func coverageCountsOnlyReferencedRegistryMembers() {
        let wait = PexFixture.runtimeFunction(
            returnType: "None",
            flags: .native,
            instructions: []
        )
        let utility = object("Utility", functions: [("Wait", wait)])
        let caller = PexFixture.runtimeObject(
            name: "Caller",
            states: [PapyrusTestSupport.state(functions: [(
                "Run",
                PexFixture.runtimeFunction(instructions: [
                    PapyrusTestSupport.instruction(
                        .callStatic,
                        .identifier("Utility"),
                        .identifier("Wait"),
                        .identifier("::nonevar"),
                        .integer(1),
                        .float(1)
                    )
                ])
            )])]
        )
        let census = PexNativeCensus(
            files: [PexFixture.runtimeFile(objects: [utility, caller])]
        )
        #expect(census.coverage(in: .empty) == PexNativeCoverage(
            implemented: 0, referenced: 1
        ))
        #expect(census.coverage(in: .standard) == PexNativeCoverage(
            implemented: 1, referenced: 1
        ))
    }

    private func callerObject() -> PexObject {
        let property = PexProperty(
            name: "Target",
            typeName: "NativeBase",
            documentation: "",
            userFlags: 0,
            flags: [.automatic],
            automaticVariableName: "::Target_var",
            readHandler: nil,
            writeHandler: nil
        )
        let run = PexFixture.runtimeFunction(
            parameters: [PexTypedName(name: "argument", typeName: "NativeBase")],
            locals: [PexTypedName(name: "local", typeName: "NativeBase")],
            instructions: [
                callMethod(receiver: "self"),
                callMethod(receiver: "argument"),
                callMethod(receiver: "local"),
                callMethod(receiver: "::Target_var"),
                PapyrusTestSupport.instruction(
                    .callStatic,
                    .identifier("Utility"),
                    .identifier("Wait"),
                    .identifier("::nonevar"),
                    .integer(1),
                    .float(1)
                )
            ]
        )
        return PexFixture.runtimeObject(
            name: "Caller",
            parent: "NativeBase",
            variables: [
                PexVariable(
                    name: "::Target_var",
                    typeName: "NativeBase",
                    userFlags: 0,
                    initialValue: .null
                )
            ],
            properties: [property],
            states: [PapyrusTestSupport.state(functions: [("Run", run)])]
        )
    }

    private func callMethod(receiver: String) -> PexInstruction {
        PapyrusTestSupport.instruction(
            .callMethod,
            .identifier("Touch"),
            .identifier(receiver),
            .identifier("::nonevar"),
            .integer(0)
        )
    }

    private func object(
        _ name: String,
        functions: [(String, PexFunction)]
    ) -> PexObject {
        PexFixture.runtimeObject(
            name: name,
            states: [PapyrusTestSupport.state(functions: functions)]
        )
    }
}
