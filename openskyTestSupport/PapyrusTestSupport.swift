import Foundation
@testable import opensky
import Testing

enum PapyrusTestSupport {
    static func instruction(
        _ opcode: PexOpcode,
        _ operands: PexValue...
    ) -> PexInstruction {
        PexInstruction(opcode: opcode, operands: operands)
    }

    static func state(
        _ name: String = "",
        functions: [(String, PexFunction)]
    ) -> PexState {
        PexState(
            name: name,
            functions: functions.map { PexNamedFunction(name: $0.0, function: $0.1) }
        )
    }

    static func runtime(
        objects: [PexObject],
        nativeDispatch: PapyrusNativeDispatch = PapyrusRecordingNativeDispatch(),
        limits: PapyrusLimits = .standard
    ) -> (PapyrusRuntime, PapyrusObjectHandle) {
        let runtime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: objects)],
            nativeDispatch: nativeDispatch,
            limits: limits
        )
        let handle: PapyrusObjectHandle
        do {
            handle = try runtime.makeInstance(scriptName: objects[0].name)
        } catch {
            Issue.record("Could not create Papyrus test instance: \(error)")
            handle = PapyrusObjectHandle(0)
        }
        return (runtime, handle)
    }

    static func value(_ outcome: PapyrusRunOutcome) -> PapyrusValue? {
        guard case let .completed(value) = outcome else {
            return nil
        }
        return value
    }

    static func fault(_ outcome: PapyrusRunOutcome) -> PapyrusFault? {
        guard case let .faulted(fault) = outcome else {
            return nil
        }
        return fault
    }
}
