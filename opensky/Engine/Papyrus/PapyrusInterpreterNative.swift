// Native dispatch and suspension boundary for the Papyrus interpreter.

import Foundation

nonisolated extension PapyrusInterpreter {
    func suspend(
        call: PapyrusNativeCall,
        request: PapyrusNativeSuspension,
        target: PapyrusResumeTarget
    ) -> SuspendedCall {
        let id = runtime.allocateSuspensionID()
        pendingResume = (id, target)
        runtime.tally.noteSuspension()
        return SuspendedCall(
            id: id,
            nativeCall: call,
            request: request,
            continuation: PapyrusContinuation(interpreter: self)
        )
    }

    func nativeFlow(
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

    func nativeOutcome(
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
        let result = runtime.nativeDispatch.invoke(call)
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

    private func nativeReturnType(_ destination: PexValue) -> PapyrusType {
        guard let frame = frames.last else { return .none }
        if
            case let .identifier(name) = destination,
            PapyrusRuntime.matches(name, "::nonevar")
            || PapyrusRuntime.matches(name, "none")
        {
            return .none
        }
        return (try? destinationType(destination, frame: frame)) ?? .none
    }
}
