// Bounded, explicit-frame Skyrim Papyrus interpreter.
//
// Calls push `PapyrusFrame` values onto `frames`; Swift recursion is never used
// for bytecode. An invoked native may suspend, retaining this interpreter
// through `SuspendedCall`. Each resume starts a new instruction slice.

import Foundation
public import OpenSkyFormatsPEX
public import OpenSkyScriptingInterface

nonisolated enum PapyrusFlow {
    case next
    case jump(Int)
    case returned(PapyrusValue)
    case suspended(SuspendedCall)
}

nonisolated enum PapyrusResumeTarget: Sendable {
    case root
    case assign(PexValue)
}

final class PapyrusContinuation {
    private let resumeInterpreter: (UInt64, PapyrusValue) -> PapyrusRunOutcome
    private var consumed = false

    init(resume: @escaping (UInt64, PapyrusValue) -> PapyrusRunOutcome) {
        resumeInterpreter = resume
    }

    func resume(id: UInt64, returning value: PapyrusValue) -> PapyrusRunOutcome {
        guard !consumed else {
            return .faulted(.invalidResume)
        }
        consumed = true
        return resumeInterpreter(id, value)
    }
}

extension PapyrusRuntime {
    final class Interpreter {
        let runtime: PapyrusRuntime
        var frames: [PapyrusFrame] = []

        private var remainingBudget: Int
        var pendingResume: (id: UInt64, target: PapyrusResumeTarget)?

        init(runtime: PapyrusRuntime) {
            self.runtime = runtime
            remainingBudget = runtime.limits.instructionBudget
        }

        var natives: PapyrusNativeCalls {
            PapyrusNativeCalls(interpreter: self)
        }

        var instructionIndex: Int {
            frames.last.map { max(0, $0.instructionIndex - 1) } ?? 0
        }

        func invoke(
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
                    return natives.nativeOutcome(call, target: .root)
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

        /// Runs the `Set` function of the full property `name` with `value`.
        func setProperty(
            _ name: String,
            on handle: PapyrusObjectHandle,
            to value: PapyrusValue
        ) -> PapyrusRunOutcome {
            do {
                guard let instance = runtime.instance(for: handle) else {
                    throw PapyrusFault.missingInstance(handle)
                }
                guard
                    let resolved = try resolveProperty(name, instance: instance),
                    let setter = propertyHandler(of: resolved, writing: true)
                else {
                    throw PapyrusFault.missingProperty(
                        instruction: 0, script: instance.rootScriptName, property: name
                    )
                }
                try pushFrame(
                    setter,
                    instanceHandle: handle,
                    arguments: [value],
                    completion: .root
                )
                return run()
            } catch let error as PapyrusFault {
                return fault(error)
            } catch {
                return fault(.invalidOperand(instruction: 0, detail: String(describing: error)))
            }
        }

        func invokeStatic(
            _ functionName: String,
            on scriptName: String,
            arguments: [PapyrusValue]
        ) -> PapyrusRunOutcome {
            do {
                guard let resolved = staticFunction(functionName, script: scriptName) else {
                    throw PapyrusFault.missingFunction(
                        instruction: 0, script: scriptName, function: functionName
                    )
                }
                if resolved.function.flags.contains(.native) {
                    let call = PapyrusNativeCall(
                        kind: .staticFunction,
                        scriptName: resolved.script.name,
                        functionName: functionName,
                        receiver: nil,
                        arguments: arguments,
                        returnType: PapyrusType(name: resolved.function.returnTypeName)
                    )
                    return natives.nativeOutcome(call, target: .root)
                }
                try pushFrame(
                    resolved,
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

        func resume(id: UInt64, returning value: PapyrusValue) -> PapyrusRunOutcome {
            guard let pending = pendingResume, pending.id == id else {
                return fault(.invalidResume)
            }
            pendingResume = nil
            remainingBudget = runtime.limits.instructionBudget
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

        func run() -> PapyrusRunOutcome {
            do {
                while let frame = frames.last {
                    guard frame.instructionIndex < frame.function.instructions.count else {
                        if let result = try complete(frame.defaultReturnValue) {
                            return .completed(result)
                        }
                        continue
                    }
                    let index = frame.instructionIndex
                    guard remainingBudget > 0, runtime.stepInstructionsLeft > 0 else {
                        return .suspended(natives.yieldSlice())
                    }
                    remainingBudget -= 1
                    runtime.stepInstructionsLeft -= 1
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

        func pushFrame(
            _ resolved: PapyrusResolvedFunction,
            instanceHandle: PapyrusObjectHandle?,
            arguments: [PapyrusValue],
            completion: PapyrusFrameCompletion
        ) throws(PapyrusFault) {
            guard frames.count < runtime.limits.callDepth else {
                throw .callDepthExceeded(instruction: instructionIndex)
            }
            let compiled = resolved.compiled
            let frame = PapyrusFrame(
                owner: resolved.owner,
                compiled: compiled,
                instanceHandle: instanceHandle,
                completion: completion
            )
            for (index, slot) in compiled.argumentSlots.enumerated() {
                guard let slot else { continue }
                let value = arguments.indices.contains(index)
                    ? arguments[index]
                    : compiled.slotDefaults[slot]
                try frame.setSlot(slot, to: cast(value, to: compiled.slotTypes[slot]))
            }
            frames.append(frame)
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
}

/// The interpreter's native calls: dispatch, game-timing delay, and suspension.
struct PapyrusNativeCalls {
    let interpreter: PapyrusRuntime.Interpreter

    var runtime: PapyrusRuntime {
        interpreter.runtime
    }
}

nonisolated public struct SuspendedCall {
    public let id: UInt64
    public let nativeCall: PapyrusNativeCall
    public let request: PapyrusNativeSuspension
    let continuation: PapyrusContinuation
    /// True for a used-up instruction slice. A latent call releases its instance, so
    /// other events on it run meanwhile (CK wiki "Threading Notes (Papyrus)").
    public let holdsInstance: Bool
}
