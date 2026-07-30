// M11.1 headless acceptance: native dispatch, latency, fallback, determinism.

import Foundation
@testable import opensky
import Testing

struct M11AcceptanceTests {
    private struct Evidence: Equatable {
        let value: PapyrusValue
        let tally: PapyrusTallySnapshot
        let log: [String]
    }

    @Test func syntheticNativeProgramIsDeterministicTwice() throws {
        let first = try executeSyntheticProgram()
        let second = try executeSyntheticProgram()

        #expect(first == second)
        #expect(first.tally.nativeCallTotal == 4)
        #expect(first.tally.unimplementedNativeTotal == 1)
        #expect(first.tally.suspensionTotal == 1)
        #expect(first.tally.faultTotal == 0)
        #expect(first.log.contains("Trace: M11.1"))
    }

    @Test func deferredAnimationReturnsSuccessAndUsesItsNamedBucket() {
        let function = PexFixture.runtimeFunction(
            returnType: "Bool",
            flags: .native,
            parameters: [PexTypedName(name: "eventName", typeName: "String")],
            instructions: []
        )
        let object = PexFixture.runtimeObject(
            name: "ObjectReference",
            states: [PapyrusTestSupport.state(functions: [
                ("PlayAnimation", function)
            ])]
        )
        let runtime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: [object])]
        )

        #expect(PapyrusTestSupport.value(runtime.invokeStatic(
            "PlayAnimation",
            on: "ObjectReference",
            arguments: [.string("Open")]
        )) == .boolean(true))
        #expect(runtime.tally.deferredAnimationTotal == 1)
        #expect(runtime.tally.unimplementedNativeTotal == 0)
    }

    private func executeSyntheticProgram() throws -> Evidence {
        let context = PapyrusNativeContext(seed: 0x170)
        var registry = PapyrusNativeRegistry(context: context)
        PapyrusNativeFunctions.install(into: &registry)
        let script = syntheticScript()
        let runtime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: [script])],
            nativeDispatch: registry
        )
        let handle = try runtime.makeInstance(scriptName: script.name)
        let scheduler = PapyrusScheduler(runtime: runtime, fixedStepSeconds: 0.25)
        scheduler.schedule(runtime.invoke("Run", on: handle))
        #expect(scheduler.tick().isEmpty)
        let outcomes = scheduler.tick()
        let outcome = try #require(outcomes.first)
        let value = try #require(PapyrusTestSupport.value(outcome))
        return Evidence(
            value: value,
            tally: runtime.tally.snapshot,
            log: context.log.messages
        )
    }

    private func syntheticScript() -> PexObject {
        let instructions = [
            staticCall(
                script: "Debug",
                function: "Trace",
                destination: "::nonevar",
                arguments: [.string("M11.1")]
            ),
            staticCall(
                script: "Utility",
                function: "RandomInt",
                destination: "roll",
                arguments: [.integer(10), .integer(20)]
            ),
            staticCall(
                script: "Utility",
                function: "Wait",
                destination: "::nonevar",
                arguments: [.float(0.5)]
            ),
            staticCall(
                script: "Missing",
                function: "Query",
                destination: "unknown",
                arguments: []
            ),
            PapyrusTestSupport.instruction(.returnValue, .identifier("roll"))
        ]
        let run = PexFixture.runtimeFunction(
            returnType: "Int",
            locals: [
                PexTypedName(name: "roll", typeName: "Int"),
                PexTypedName(name: "unknown", typeName: "String")
            ],
            instructions: instructions
        )
        return PexFixture.runtimeObject(
            name: "M11Synthetic",
            states: [PapyrusTestSupport.state(functions: [("Run", run)])]
        )
    }

    private func staticCall(
        script: String,
        function: String,
        destination: String,
        arguments: [PexValue]
    ) -> PexInstruction {
        PexInstruction(
            opcode: .callStatic,
            operands: [
                .identifier(script),
                .identifier(function),
                .identifier(destination),
                .integer(Int32(arguments.count))
            ] + arguments
        )
    }
}
