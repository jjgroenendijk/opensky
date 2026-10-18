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
        let value: PapyrusValue
        switch dispatch(typedCall) {
        case let .returned(returned), let .deviated(returned, _):
            value = returned
        case .failed:
            value = typedCall.returnType.defaultValue
        case let .suspended(request):
            return .suspended(suspend(
                call: typedCall,
                request: request,
                target: .assign(destination)
            ))
        }
        if let delayed = delay(typedCall, returning: value, target: .assign(destination)) {
            return .suspended(delayed)
        }
        guard let frame = frames.last else {
            return .returned(value)
        }
        try write(value, to: destination, frame: frame)
        return .next
    }

    public func nativeOutcome(
        _ call: PapyrusNativeCall,
        target: PapyrusResumeTarget
    ) -> PapyrusRunOutcome {
        let value: PapyrusValue
        switch dispatch(call) {
        case let .returned(returned), let .deviated(returned, _):
            value = returned
        case .failed:
            value = call.returnType.defaultValue
        case let .suspended(request):
            return .suspended(suspend(call: call, request: request, target: target))
        }
        if let delayed = delay(call, returning: value, target: target) {
            return .suspended(delayed)
        }
        return .completed(value)
    }

    /// Under game timing a native that is not non-delayed answers on the next fixed step,
    /// and releases its instance meanwhile (CK wiki "Threading Notes (Papyrus)").
    private func delay(
        _ call: PapyrusNativeCall,
        returning value: PapyrusValue,
        target: PapyrusResumeTarget
    ) -> SuspendedCall? {
        guard
            runtime.nativeTiming == .game,
            PapyrusNativeTimingTable.timing(of: call.key) != .nonDelayed
        else { return nil }
        runtime.tally.noteDelayedNative()
        return suspend(call: call, request: .realSecondsAnswering(0, value), target: target)
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
