// Method, parent, and static call opcodes.

import Foundation

nonisolated extension PapyrusInterpreter {
    func callOp(
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
        let functionName = try name(from: operands[0])
        let receiverValue = try read(operands[1], frame: frame)
        guard case let .object(handle) = receiverValue else {
            throw .typeMismatch(
                instruction: instructionIndex,
                expected: "Object",
                actual: receiverValue.typeName
            )
        }
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
                functionName: functionName,
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
                functionName: functionName,
                receiver: handle,
                arguments: arguments,
                destination: operands[2]
            )
        }
        return try nativeFlow(
            nativeCall(
                kind: .method,
                script: instance.rootScriptName,
                function: functionName,
                receiver: handle,
                arguments: arguments
            ),
            destination: operands[2]
        )
    }

    private func callParent(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(3, instruction: instruction)
        let functionName = try name(from: operands[0])
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
                    script: resolved.script.name,
                    function: functionName,
                    receiver: handle,
                    arguments: arguments
                ),
                destination: operands[1]
            )
        }
        return try nativeFlow(
            nativeCall(
                kind: .parent,
                script: parentName,
                function: functionName,
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
        let functionName = try name(from: operands[1])
        let arguments = try callArguments(operands, countIndex: 3, frame: frame)
        if
            let script = runtime.script(named: scriptName),
            let function = function(named: functionName, state: "", script: script),
            !function.flags.contains(.native)
        {
            try pushFrame(
                PapyrusResolvedFunction(script: script, function: function),
                instanceHandle: nil,
                arguments: arguments,
                completion: .assign(operands[2])
            )
            return .next
        }
        return try nativeFlow(
            nativeCall(
                kind: .staticFunction,
                script: scriptName,
                function: functionName,
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
            instance.activeState = stateName
            try write(.none, to: destination, frame: frame)
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

    private func name(from operand: PexValue) throws(PapyrusFault) -> String {
        guard let name = operand.stringValue else {
            throw .invalidOperand(
                instruction: instructionIndex,
                detail: "call name is not a string-table value"
            )
        }
        return name
    }

    private func nativeCall(
        kind: PapyrusNativeCallKind,
        script: String,
        function: String,
        receiver: PapyrusObjectHandle?,
        arguments: [PapyrusValue]
    ) -> PapyrusNativeCall {
        PapyrusNativeCall(
            kind: kind,
            scriptName: script,
            functionName: function,
            receiver: receiver,
            arguments: arguments
        )
    }

    private func externalMethodCall(
        functionName: String,
        receiverOperand: PexValue,
        receiver: PapyrusObjectHandle,
        arguments: [PapyrusValue],
        frame: PapyrusFrame
    ) -> PapyrusNativeCall {
        nativeCall(
            kind: .method,
            script: receiverScriptName(receiverOperand, frame: frame),
            function: functionName,
            receiver: receiver,
            arguments: arguments
        )
    }

    private func resolvedMethodFlow(
        _ resolved: PapyrusResolvedFunction,
        functionName: String,
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
            script: resolved.script.name,
            function: functionName,
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
