// Native dispatch and suspension boundary for the Papyrus interpreter.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

extension PapyrusInterpreter {
    public func suspend(
        call: PapyrusNativeCall,
        request: PapyrusNativeSuspension,
        target: PapyrusResumeTarget,
        holdsInstance: Bool = false
    ) -> SuspendedCall {
        let id = runtime.allocateSuspensionID()
        pendingResume = (id, target)
        runtime.tally.noteSuspension()
        return SuspendedCall(
            id: id,
            nativeCall: call,
            request: request,
            continuation: PapyrusContinuation(interpreter: self),
            holdsInstance: holdsInstance
        )
    }

    /// A used-up slice waits one tick and goes on, as the game's VM time-slices scripts
    /// (CK wiki "Papyrus INI Settings", `fUpdateBudgetMS`).
    func yieldSlice() -> SuspendedCall {
        let call = PapyrusNativeCall(
            kind: .staticFunction,
            scriptName: "Utility",
            functionName: "Wait",
            receiver: nil,
            arguments: [.float(0)],
            returnType: .none
        )
        return suspend(
            call: call, request: .realSeconds(0), target: .assign(.null), holdsInstance: true
        )
    }

    public func nativeFlow(
        _ call: PapyrusNativeCall,
        destination: PexValue
    ) throws(PapyrusFault) -> PapyrusFlow {
        let typedCall = call.returning(nativeReturnType(destination))
        switch dispatch(typedCall) {
        case let .returned(value):
            guard let frame = frames.last else {
                return .returned(.none)
            }
            try write(value, to: destination, frame: frame)
            return .next
        case .failed:
            guard let frame = frames.last else {
                return .returned(typedCall.returnType.defaultValue)
            }
            try write(typedCall.returnType.defaultValue, to: destination, frame: frame)
            return .next
        case let .suspended(request):
            return .suspended(suspend(
                call: typedCall,
                request: request,
                target: .assign(destination)
            ))
        case let .deviated(value, _):
            guard let frame = frames.last else {
                return .returned(value)
            }
            try write(value, to: destination, frame: frame)
            return .next
        }
    }

    public func nativeOutcome(
        _ call: PapyrusNativeCall,
        target: PapyrusResumeTarget
    ) -> PapyrusRunOutcome {
        switch dispatch(call) {
        case let .returned(value):
            .completed(value)
        case .failed:
            .completed(call.returnType.defaultValue)
        case let .suspended(request):
            .suspended(suspend(call: call, request: request, target: target))
        case let .deviated(value, _):
            .completed(value)
        }
    }

    private func dispatch(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        runtime.tally.noteNative(call)
        let result = runtime.nativeDispatch.invoke(withStack(call))
        switch result {
        case let .failed(failure):
            runtime.tally.noteNativeFailure(failure, call: call)
        case let .deviated(_, deviation):
            runtime.tally.noteDeviation(deviation)
        case .returned, .suspended:
            break
        }
        return result
    }

    /// `Debug.TraceStack` prints the callers, which only the interpreter knows.
    private func withStack(_ call: PapyrusNativeCall) -> PapyrusNativeCall {
        guard
            call.scriptName.caseInsensitiveCompare("Debug") == .orderedSame,
            call.functionName.caseInsensitiveCompare("TraceStack") == .orderedSame
        else { return call }
        let lines = frames.reversed().map { frame in
            "  \(frame.ownerScript.name) at instruction \(max(0, frame.instructionIndex - 1))"
        }
        var arguments = Array(call.arguments.prefix(2))
        while arguments.count < 2 {
            arguments.append(arguments.isEmpty ? .string("Tracing stack on request") : .integer(0))
        }
        return PapyrusNativeCall(
            kind: call.kind,
            scriptName: call.scriptName,
            functionName: call.functionName,
            receiver: call.receiver,
            arguments: arguments + [.string(lines.joined(separator: "\n"))],
            returnType: call.returnType,
            key: call.key
        )
    }

    func nativeReturnType(_ destination: PexValue) -> PapyrusType {
        guard let frame = frames.last else { return .none }
        if case let .identifier(name) = destination, frame.compiled.binding(for: name).isDiscard {
            return .none
        }
        return (try? destinationType(destination, frame: frame)) ?? .none
    }
}
