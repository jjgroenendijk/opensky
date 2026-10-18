// Method, parent, and static call opcodes.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

extension PapyrusInterpreter {
    public func callOp(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow? {
        switch instruction.opcode {
        case .callMethod:
            try callMethod(instruction, frame: frame)
        case .callParent:
            try callParent(instruction, frame: frame)
        case .callStatic:
            try callStatic(instruction, frame: frame)
        default:
            nil
        }
    }

    private func callMethod(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(4, instruction: instruction)
        let function = try callName(operands[0], frame: frame)
        let functionName = function.spelling
        let receiverValue = try read(operands[1], frame: frame)
        if receiverValue == .none {
            // The game logs "Cannot call ... on a None object" and the script goes on.
            runtime.tally.noteNoneReceiver()
            try write(nativeReturnType(operands[2]).defaultValue, to: operands[2], frame: frame)
            return .next
        }
        guard case let .object(value) = receiverValue else {
            throw .typeMismatch(
                instruction: instructionIndex,
                expected: "Object",
                actual: receiverValue.typeName
            )
        }
        let handle = declaredReceiver(value, operand: operands[1], frame: frame)
        let arguments = try callArguments(operands, countIndex: 3, frame: frame)
        if
            let intrinsic = try intrinsic(
                functionName,
                receiver: handle,
                arguments: arguments,
                destination: operands[2],
                frame: frame
            )
        {
            return intrinsic
        }
        guard let instance = runtime.instance(for: handle) else {
            let call = externalMethodCall(
                function,
                receiverOperand: operands[1],
                receiver: handle,
                arguments: arguments,
                frame: frame
            )
            return try nativeFlow(call, destination: operands[2])
        }
        if let resolved = try resolveMethod(functionName, instance: instance) {
            return try resolvedMethodFlow(
                resolved,
                function: function,
                receiver: handle,
                arguments: arguments,
                destination: operands[2]
            )
        }
        let root = instance.rootScriptName
        return try nativeFlow(
            nativeCall(
                kind: .method, script: (root, runtime.index(named: root)?.key), function: function,
                receiver: handle, arguments: arguments
            ),
            destination: operands[2]
        )
    }

    private func callParent(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(3, instruction: instruction)
        let function = try callName(operands[0], frame: frame)
        let functionName = function.spelling
        guard let handle = frame.instanceHandle, let instance = runtime.instance(for: handle) else {
            throw .invalidOperand(
                instruction: instructionIndex,
                detail: "parent call has no instance"
            )
        }
        let arguments = try callArguments(operands, countIndex: 2, frame: frame)
        let parentName = frame.ownerScript.parentClassName
        if
            let resolved = try resolveMethod(
                functionName,
                instance: instance,
                startingAt: parentName
            )
        {
            if !resolved.function.flags.contains(.native) {
                try pushFrame(
                    resolved,
                    instanceHandle: handle,
                    arguments: arguments,
                    completion: .assign(operands[1])
                )
                return .next
            }
            return try nativeFlow(
                nativeCall(
                    kind: .parent,
                    script: (resolved.script.name, resolved.owner.key),
                    function: function,
                    receiver: handle,
                    arguments: arguments
                ),
                destination: operands[1]
            )
        }
        return try nativeFlow(
            nativeCall(
                kind: .parent,
                script: (parentName, runtime.index(named: parentName)?.key),
                function: function,
                receiver: handle,
                arguments: arguments
            ),
            destination: operands[1]
        )
    }

    private func callStatic(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(4, instruction: instruction)
        let scriptName = try name(from: operands[0])
        let function = try callName(operands[1], frame: frame)
        let functionName = function.spelling
        let arguments = try callArguments(operands, countIndex: 3, frame: frame)
        if runtime.index(named: scriptName) == nil {
            _ = runtime.loadScript?(scriptName)
        }
        if
            let resolved = staticFunction(functionName, script: scriptName),
            !resolved.function.flags.contains(.native)
        {
            try pushFrame(
                resolved,
                instanceHandle: nil,
                arguments: arguments,
                completion: .assign(operands[2])
            )
            return .next
        }
        return try nativeFlow(
            nativeCall(
                kind: .staticFunction,
                script: (scriptName, function.scriptKey),
                function: function,
                receiver: nil,
                arguments: arguments
            ),
            destination: operands[2]
        )
    }

    private func callArguments(
        _ operands: [PexValue],
        countIndex: Int,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> [PapyrusValue] {
        guard
            operands.indices.contains(countIndex),
            case let .integer(rawCount) = operands[countIndex],
            rawCount >= 0
        else {
            throw .invalidOperand(
                instruction: instructionIndex,
                detail: "call argument count is not a non-negative integer"
            )
        }
        let count = Int(rawCount)
        let start = countIndex + 1
        guard operands.count >= start + count else {
            throw .invalidOperand(
                instruction: instructionIndex,
                detail: "call argument list is truncated"
            )
        }
        var arguments: [PapyrusValue] = []
        arguments.reserveCapacity(count)
        for operand in operands[start ..< start + count] {
            try arguments.append(read(operand, frame: frame))
        }
        return arguments
    }

    private func intrinsic(
        _ functionName: String,
        receiver: PapyrusObjectHandle,
        arguments: [PapyrusValue],
        destination: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow? {
        if PapyrusRuntime.matches(functionName, "GotoState") {
            guard let instance = runtime.instance(for: receiver) else {
                throw .missingInstance(receiver)
            }
            guard case let .string(stateName) = arguments.first else {
                throw .typeMismatch(
                    instruction: instructionIndex,
                    expected: "String",
                    actual: arguments.first?.typeName ?? "missing"
                )
            }
            try write(.none, to: destination, frame: frame)
            try gotoState(stateName, instance: instance, receiver: receiver)
            return .next
        }
        if PapyrusRuntime.matches(functionName, "GetState") {
            guard let instance = runtime.instance(for: receiver) else {
                throw .missingInstance(receiver)
            }
            try write(.string(instance.activeState), to: destination, frame: frame)
            return .next
        }
        return nil
    }

    /// Runs `OnEndState` of the old state, then `OnBeginState` of the new one, as the
    /// game's `GotoState` does (CK wiki, "States (Papyrus)"). The end frame goes on
    /// top so it runs first; `GetState` already reads the new state inside it.
    private func gotoState(
        _ stateName: String,
        instance: PapyrusInstance,
        receiver: PapyrusObjectHandle
    ) throws(PapyrusFault) {
        let end = try stateHook(PapyrusEngineEvents.onEndState, instance: instance)
        instance.activeState = stateName
        let begin = try stateHook(PapyrusEngineEvents.onBeginState, instance: instance)
        for hook in [begin, end].compactMap(\.self) {
            try pushFrame(hook, instanceHandle: receiver, arguments: [], completion: .discard)
        }
    }

    private func stateHook(
        _ name: String,
        instance: PapyrusInstance
    ) throws(PapyrusFault) -> PapyrusResolvedFunction? {
        guard let hook = try resolveMethod(name, instance: instance) else { return nil }
        return hook.function.flags.contains(.native) ? nil : hook
    }

    private func name(from operand: PexValue) throws(PapyrusFault) -> String {
        guard let name = operand.stringValue else {
            throw .invalidOperand(
                instruction: instructionIndex,
                detail: "call name is not a string-table value"
            )
        }
        return name
    }

    /// `script.key` and `function.key` are the folded names; either nil folds at the call.
    private func nativeCall(
        kind: PapyrusNativeCallKind,
        script: (name: String, key: String?),
        function: CallName,
        receiver: PapyrusObjectHandle?,
        arguments: [PapyrusValue]
    ) -> PapyrusNativeCall {
        let key = script.key.flatMap { scriptKey in
            function.key.map {
                PapyrusNativeKey(foldedScriptName: scriptKey, foldedFunctionName: $0)
            }
        }
        return PapyrusNativeCall(
            kind: kind,
            scriptName: script.name,
            functionName: function.spelling,
            receiver: receiver,
            arguments: arguments,
            key: key
        )
    }

    /// The call name operand with the folded names stored on the instruction at load.
    private func callName(
        _ operand: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> CallName {
        let spelling = try name(from: operand)
        let keys = frame.compiled.callNameKeys(at: frame.instructionIndex - 1, spelling: spelling)
        return CallName(spelling: spelling, key: keys?.function, scriptKey: keys?.script)
    }

    private func externalMethodCall(
        _ function: CallName,
        receiverOperand: PexValue,
        receiver: PapyrusObjectHandle,
        arguments: [PapyrusValue],
        frame: PapyrusFrame
    ) -> PapyrusNativeCall {
        let declared = receiverScriptName(receiverOperand, frame: frame)
        let owner = nativeOwner(of: function.spelling, from: declared)
        return nativeCall(
            kind: .method,
            script: (
                owner?.script.name ?? declared,
                owner?.key ?? runtime.index(named: declared)?.key
            ),
            function: function,
            receiver: receiver,
            arguments: arguments
        )
    }

    /// The script in `declared`'s parent chain that declares `functionName` native, as a
    /// call on an instance resolves it. Nil when no loaded script does.
    private func nativeOwner(
        of functionName: String,
        from declared: String
    ) -> PapyrusScriptIndex? {
        guard let chain = try? runtime.indexChain(from: declared) else { return nil }
        return chain.first { $0.declaresNative(functionName) }
    }

    private func resolvedMethodFlow(
        _ resolved: PapyrusResolvedFunction,
        function: CallName,
        receiver: PapyrusObjectHandle,
        arguments: [PapyrusValue],
        destination: PexValue
    ) throws(PapyrusFault) -> PapyrusFlow {
        if !resolved.function.flags.contains(.native) {
            try pushFrame(
                resolved,
                instanceHandle: receiver,
                arguments: arguments,
                completion: .assign(destination)
            )
            return .next
        }
        let call = nativeCall(
            kind: .method,
            script: (resolved.script.name, resolved.owner.key),
            function: function,
            receiver: receiver,
            arguments: arguments
        )
        return try nativeFlow(call, destination: destination)
    }

    private func receiverScriptName(
        _ operand: PexValue,
        frame: PapyrusFrame
    ) -> String {
        guard case let .object(name) = declaredType(of: operand, frame: frame) else {
            return "Object"
        }
        return name
    }
}

/// A call name as the script spells it, with the folded names stored at load.
private struct CallName {
    let spelling: String
    let key: String?
    let scriptKey: String?
}
