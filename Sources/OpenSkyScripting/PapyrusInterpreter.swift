// Bounded, explicit-frame Skyrim Papyrus interpreter.
//
// Calls push `PapyrusFrame` values onto `frames`; Swift recursion is never used
// for bytecode. An invoked native may suspend, retaining this interpreter and
// its remaining budget through `SuspendedCall`.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

nonisolated public enum PapyrusFlow {
    case next
    case jump(Int)
    case returned(PapyrusValue)
    case suspended(SuspendedCall)
}

nonisolated public enum PapyrusResumeTarget: Sendable {
    case root
    case assign(PexValue)
}

nonisolated public struct SuspendedCall {
    public let id: UInt64
    public let nativeCall: PapyrusNativeCall
    public let request: PapyrusNativeSuspension
    public let continuation: PapyrusContinuation
}

public final class PapyrusContinuation {
    private let interpreter: PapyrusInterpreter
    private var consumed = false

    public init(interpreter: PapyrusInterpreter) {
        self.interpreter = interpreter
    }

    public func resume(id: UInt64, returning value: PapyrusValue) -> PapyrusRunOutcome {
        guard !consumed else {
            return .faulted(.invalidResume)
        }
        consumed = true
        return interpreter.resume(id: id, returning: value)
    }
}

public final class PapyrusInterpreter {
    public let runtime: PapyrusRuntime
    public var frames: [PapyrusFrame] = []

    private var remainingBudget: Int
    public var pendingResume: (id: UInt64, target: PapyrusResumeTarget)?

    public init(runtime: PapyrusRuntime) {
        self.runtime = runtime
        remainingBudget = runtime.limits.instructionBudget
    }

    public var instructionIndex: Int {
        frames.last.map { max(0, $0.instructionIndex - 1) } ?? 0
    }

    public func invoke(
        _ functionName: String,
        on handle: PapyrusObjectHandle,
        arguments: [PapyrusValue]
    ) -> PapyrusRunOutcome {
        do {
            guard let instance = runtime.instance(for: handle) else {
                throw PapyrusFault.missingInstance(handle)
            }
            guard let resolved = try resolveMethod(functionName, instance: instance) else {
                throw PapyrusFault.missingFunction(
                    instruction: 0,
                    script: instance.rootScriptName,
                    function: functionName
                )
            }
            if resolved.function.flags.contains(.native) {
                let call = PapyrusNativeCall(
                    kind: .method,
                    scriptName: resolved.script.name,
                    functionName: functionName,
                    receiver: handle,
                    arguments: arguments,
                    returnType: PapyrusType(name: resolved.function.returnTypeName)
                )
                return nativeOutcome(call, target: .root)
            }
            try pushFrame(
                resolved,
                instanceHandle: handle,
                arguments: arguments,
                completion: .root
            )
            return run()
        } catch let error as PapyrusFault {
            return fault(error)
        } catch {
            return fault(.invalidOperand(instruction: 0, detail: String(describing: error)))
        }
    }

    public func invokeStatic(
        _ functionName: String,
        on scriptName: String,
        arguments: [PapyrusValue]
    ) -> PapyrusRunOutcome {
        do {
            guard let script = runtime.script(named: scriptName) else {
                throw PapyrusFault.missingFunction(
                    instruction: 0, script: scriptName, function: functionName
                )
            }
            guard let function = function(named: functionName, state: "", script: script) else {
                throw PapyrusFault.missingFunction(
                    instruction: 0, script: scriptName, function: functionName
                )
            }
            if function.flags.contains(.native) {
                let call = PapyrusNativeCall(
                    kind: .staticFunction,
                    scriptName: script.name,
                    functionName: functionName,
                    receiver: nil,
                    arguments: arguments,
                    returnType: PapyrusType(name: function.returnTypeName)
                )
                return nativeOutcome(call, target: .root)
            }
            try pushFrame(
                PapyrusResolvedFunction(script: script, function: function),
                instanceHandle: nil,
                arguments: arguments,
                completion: .root
            )
            return run()
        } catch let error as PapyrusFault {
            return fault(error)
        } catch {
            return fault(.invalidOperand(instruction: 0, detail: String(describing: error)))
        }
    }

    public func resume(id: UInt64, returning value: PapyrusValue) -> PapyrusRunOutcome {
        guard let pending = pendingResume, pending.id == id else {
            return fault(.invalidResume)
        }
        pendingResume = nil
        switch pending.target {
        case .root:
            return .completed(value)
        case let .assign(destination):
            do {
                guard let frame = frames.last else {
                    throw PapyrusFault.invalidResume
                }
                try write(value, to: destination, frame: frame)
                return run()
            } catch let error as PapyrusFault {
                return fault(error)
            } catch {
                return fault(
                    .invalidOperand(
                        instruction: instructionIndex,
                        detail: String(describing: error)
                    )
                )
            }
        }
    }

    public func run() -> PapyrusRunOutcome {
        do {
            while let frame = frames.last {
                guard frame.instructionIndex < frame.function.instructions.count else {
                    if let result = try complete(frame.defaultReturnValue) {
                        return .completed(result)
                    }
                    continue
                }
                let index = frame.instructionIndex
                try consumeBudget(at: index)
                let instruction = frame.function.instructions[index]
                runtime.tally.noteInstruction(instruction.opcode)
                frame.instructionIndex += 1
                switch try step(instruction, frame: frame) {
                case .next:
                    continue
                case let .jump(target):
                    frame.instructionIndex = target
                case let .returned(value):
                    if let result = try complete(value) {
                        return .completed(result)
                    }
                case let .suspended(call):
                    return .suspended(call)
                }
            }
            return .completed(.none)
        } catch {
            return fault(error)
        }
    }

    public func pushFrame(
        _ resolved: PapyrusResolvedFunction,
        instanceHandle: PapyrusObjectHandle?,
        arguments: [PapyrusValue],
        completion: PapyrusFrameCompletion
    ) throws(PapyrusFault) {
        guard frames.count < runtime.limits.callDepth else {
            throw .callDepthExceeded(instruction: instructionIndex)
        }
        let frame = PapyrusFrame(
            ownerScript: resolved.script,
            function: resolved.function,
            instanceHandle: instanceHandle,
            arguments: arguments,
            completion: completion
        )
        for parameter in resolved.function.parameters {
            guard
                let value = frame.localValue(named: parameter.name),
                let type = frame.localType(named: parameter.name)
            else {
                throw .invalidOperand(
                    instruction: instructionIndex,
                    detail: "missing parameter \(parameter.name)"
                )
            }
            let converted = try cast(value, to: type)
            _ = frame.setLocalValue(converted, named: parameter.name)
        }
        frames.append(frame)
    }

    private func consumeBudget(at index: Int) throws(PapyrusFault) {
        guard remainingBudget > 0 else {
            throw .budgetExhausted(instruction: index)
        }
        remainingBudget -= 1
    }

    private func complete(_ value: PapyrusValue) throws(PapyrusFault) -> PapyrusValue? {
        let completed = frames.removeLast()
        switch completed.completion {
        case .root:
            return value
        case .discard:
            return nil
        case let .assign(destination):
            guard let caller = frames.last else {
                throw .invalidOperand(
                    instruction: instructionIndex,
                    detail: "call completion has no caller"
                )
            }
            try write(value, to: destination, frame: caller)
            return nil
        }
    }

    private func fault(_ fault: PapyrusFault) -> PapyrusRunOutcome {
        var place = frames.last?.ownerScript.name
        if
            case let .missingInstance(handle) = fault,
            let receiver = runtime.describeHandle?(handle)
        {
            place = (place ?? "") + " on \(receiver)"
        }
        frames.removeAll()
        runtime.tally.noteFault(fault, in: place)
        return .faulted(fault)
    }
}
