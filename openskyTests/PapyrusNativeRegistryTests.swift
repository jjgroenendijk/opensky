// Native registry families, fallback policy, and tally evidence.

import Foundation
@testable import opensky
import Testing

struct PapyrusNativeRegistryTests {
    @Test func standardInstallIsCaseInsensitiveAndEmptyIsEmpty() {
        let standard = PapyrusNativeRegistry.standard
        // 57 before the `Actor` family (issue #375) added nine, 66 before
        // 16.7 (issue #424) added `StartCombat` and `StopCombat`, 68 before
        // 19.11 (issue #474) added the eleven spell natives, and 79 before
        // 20.3 (issue #496) added the three actor-value writes.
        #expect(standard.count == 82)
        #expect(standard.contains(
            scriptName: "form", functionName: "REGISTERFORUPDATE"
        ))
        #expect(standard.contains(scriptName: "utility", functionName: "WAIT"))
        #expect(standard.contains(scriptName: "math", functionName: "sqrt"))
        #expect(standard.contains(scriptName: "objectreference", functionName: "DISABLE"))
        #expect(standard.contains(scriptName: "globalvariable", functionName: "setvalue"))
        #expect(standard.contains(scriptName: "GAME", functionName: "getplayer"))
        #expect(standard.contains(scriptName: "quest", functionName: "SETSTAGE"))
        #expect(standard.contains(scriptName: "ACTOR", functionName: "getactorvalue"))
        #expect(standard.contains(scriptName: "actor", functionName: "KILL"))
        #expect(standard.contains(scriptName: "ACTOR", functionName: "addspell"))
        #expect(standard.contains(scriptName: "spell", functionName: "CAST"))
        // `SetActorValue` sets the *base* value, which item 20.3 gave the
        // three primaries a store for; all three writes are registered since
        // (see PapyrusNativeActorValues.swift).
        #expect(standard.contains(scriptName: "Actor", functionName: "SetActorValue"))
        #expect(standard.contains(scriptName: "ACTOR", functionName: "modactorvalue"))
        #expect(standard.contains(scriptName: "actor", functionName: "ForceActorValue"))
        #expect(!PapyrusNativeRegistry.empty.contains(
            scriptName: "Utility",
            functionName: "Wait"
        ))
    }

    @Test func unimplementedNativeReturnsItsDeclaredDefaultAndIsTallied() {
        let unknown = nativeFunction(returnType: "String")
        let script = object("Unknown", functions: [("Missing", unknown)])
        let runtime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: [script])],
            nativeDispatch: PapyrusNativeRegistry.empty
        )

        #expect(PapyrusTestSupport.value(
            runtime.invokeStatic("Missing", on: "Unknown")
        ) == .string(""))
        #expect(runtime.tally.unimplementedNativeTotal == 1)
        #expect(runtime.tally.rankedUnimplementedNatives.first?.name == "Unknown.Missing")
        #expect(runtime.tally.rankedUnimplementedNatives.first?.count == 1)
    }

    @Test func debugAndRandomFamiliesAreDeterministic() {
        let first = PapyrusNativeRegistry(
            context: PapyrusNativeContext(seed: 42)
        )
        let second = PapyrusNativeRegistry(
            context: PapyrusNativeContext(seed: 42)
        )
        var installedFirst = first
        var installedSecond = second
        PapyrusNativeFunctions.install(into: &installedFirst)
        PapyrusNativeFunctions.install(into: &installedSecond)

        let trace = call(
            "Debug", "Trace", arguments: [.string("hello")]
        )
        #expect(installedFirst.invoke(trace) == .returned(.none))
        #expect(installedFirst.context.log.messages == ["Trace: hello"])

        let random = call(
            "Utility",
            "RandomInt",
            arguments: [.integer(-10), .integer(10)],
            returnType: .integer
        )
        #expect(installedFirst.invoke(random) == installedSecond.invoke(random))
    }

    @Test func invalidArgumentsReturnTheDeclaredDefaultAndReasonTally() {
        let random = PexFixture.runtimeFunction(
            returnType: "Int",
            flags: .native,
            parameters: [
                PexTypedName(name: "minimum", typeName: "Int"),
                PexTypedName(name: "maximum", typeName: "Int")
            ],
            instructions: []
        )
        let utility = object("Utility", functions: [("RandomInt", random)])
        let runtime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: [utility])]
        )

        #expect(PapyrusTestSupport.value(runtime.invokeStatic(
            "RandomInt",
            on: "Utility",
            arguments: [.integer(9), .integer(2)]
        )) == .integer(0))
        #expect(runtime.tally.nativeFailureTotal == 1)
        #expect(runtime.tally.rankedNativeFailures.first?.name == "Utility.RandomInt")
        #expect(runtime.tally.rankedNativeFailures.first?.count == 1)
    }

    @Test func mathAndAnimationDeviationReturnHonestValues() {
        let registry = PapyrusNativeRegistry.standard
        let sqrtCall = call(
            "Math", "Sqrt", arguments: [.float(81)], returnType: .float
        )
        #expect(registry.invoke(sqrtCall) == .returned(.float(9)))

        let animation = call(
            "ObjectReference",
            "PlayAnimationAndWait",
            arguments: [.string("Open"), .string("Opened")],
            returnType: .boolean
        )
        #expect(
            registry.invoke(animation)
                == .deviated(.boolean(true), .deferredAnimation)
        )
    }

    @Test func tallyNameTablesCapWithoutCappingTotals() {
        var limits = PapyrusLimits.standard
        limits.tallyNames = 1
        let first = object(
            "First",
            functions: [("Missing", nativeFunction(returnType: "None"))]
        )
        let second = object(
            "Second",
            functions: [("Missing", nativeFunction(returnType: "None"))]
        )
        let runtime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: [first, second])],
            nativeDispatch: PapyrusNativeRegistry.empty,
            limits: limits
        )
        _ = runtime.invokeStatic("Missing", on: "First")
        _ = runtime.invokeStatic("Missing", on: "Second")
        #expect(runtime.tally.unimplementedNativeTotal == 2)
        #expect(runtime.tally.rankedUnimplementedNatives.count == 1)
        #expect(runtime.tally.unnamedUnimplementedNatives == 1)
    }

    private func call(
        _ scriptName: String,
        _ functionName: String,
        arguments: [PapyrusValue],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeCall {
        PapyrusNativeCall(
            kind: .staticFunction,
            scriptName: scriptName,
            functionName: functionName,
            receiver: nil,
            arguments: arguments,
            returnType: returnType
        )
    }

    private func nativeFunction(returnType: String) -> PexFunction {
        PexFixture.runtimeFunction(
            returnType: returnType,
            flags: .native,
            instructions: []
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
