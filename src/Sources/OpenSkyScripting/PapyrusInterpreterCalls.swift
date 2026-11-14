// Method, parent, and static call opcodes.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

extension PapyrusRuntime.Interpreter {
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
        let function = try callName(operands[0], frame: frame)
        let receiverValue = try read(operands[1], frame: frame)
        if receiverValue == .none {
            // The game logs "Cannot call ... on a None object" and the script goes on.
            runtime.tally.noteNoneReceiver()
            try write(
                natives.nativeReturnType(operands[2]).defaultValue,
                to: operands[2],
                frame: frame
            )
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
            function.mayBeStateCall,
            let intrinsic = try intrinsic(
                function.spelling,
                call: (handle, arguments),
                destination: operands[2],
                frame: frame
            )
        {
            return intrinsic
        }
        let instance = runtime.instance(for: handle)
        let target = try cachedTarget(
            frame: frame, script: instance?.rootScriptName ?? "", state: instance?.activeState ?? ""
        ) { () throws(PapyrusFault) -> PapyrusCallTarget in
            guard let instance else {
                return try externalTarget(function, receiverOperand: operands[1], frame: frame)
            }
            if let resolved = try resolveMethod(function.spelling, instance: instance) {
                return Self.target(of: resolved)
            }
            let root = instance.rootScriptName
            return .native(script: root, key: runtime.index(named: root)?.key)
        }
        return try flow(
            target,
            call: PendingCall(
                kind: .method,
                function: function,
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
        let function = try callName(operands[0], frame: frame)
        guard let handle = frame.instanceHandle, let instance = runtime.instance(for: handle) else {
            throw .invalidOperand(
                instruction: instructionIndex,
                detail: "parent call has no instance"
            )
        }
        let arguments = try callArguments(operands, countIndex: 2, frame: frame)
        let parentName = frame.ownerScript.parentClassName
        let target = try cachedTarget(
            frame: frame, script: parentName, state: instance.activeState
        ) { () throws(PapyrusFault) -> PapyrusCallTarget in
            if
                let resolved = try resolveMethod(
                    function.spelling, instance: instance, startingAt: parentName
                )
            {
                return Self.target(of: resolved)
            }
            return .native(script: parentName, key: runtime.index(named: parentName)?.key)
        }
        return try flow(
            target,
            call: PendingCall(
                kind: .parent,
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
        let arguments = try callArguments(operands, countIndex: 3, frame: frame)
        let target = try cachedTarget(
            frame: frame, script: "", state: ""
        ) { () throws(PapyrusFault) -> PapyrusCallTarget in
            if runtime.index(named: scriptName) == nil {
                _ = runtime.loadScript?(scriptName)
            }
            if
                let resolved = staticFunction(function.spelling, script: scriptName),
                !resolved.function.flags.contains(.native)
            {
                return .function(resolved)
            }
            return .native(script: scriptName, key: function.scriptKey)
        }
        return try flow(
            target,
            call: PendingCall(
                kind: .staticFunction, function: function, receiver: nil, arguments: arguments
            ),
            destination: operands[2]
        )
    }

    /// The call site's kept target while the library, the receiver's script, and its
    /// state are the ones it was found for; otherwise `resolve` finds it and it is kept.
    private func cachedTarget(
        frame: PapyrusFrame,
        script: String,
        state: String,
        resolve: () throws(PapyrusFault) -> PapyrusCallTarget
    ) throws(PapyrusFault) -> PapyrusCallTarget {
        let site = frame.instructionIndex - 1
        if
            let kept = frame.owner.callSites.site(of: frame.compiled, at: site),
            kept.holds(generation: runtime.scriptsGeneration, script: script, state: state)
        {
            return kept.target
        }
        let target = try resolve()
        // Read after `resolve`, which may load a script and so change the library.
        let found = PapyrusCallSite(
            generation: runtime.scriptsGeneration, script: script, state: state, target: target
        )
        frame.owner.callSites.keep(found, of: frame.compiled, at: site)
        return target
    }

    private static func target(of resolved: PapyrusResolvedFunction) -> PapyrusCallTarget {
        resolved.function.flags.contains(.native)
            ? .native(script: resolved.script.name, key: resolved.owner.key)
            : .function(resolved)
    }

    private func flow(
        _ target: PapyrusCallTarget,
        call: PendingCall,
        destination: PexValue
    ) throws(PapyrusFault) -> PapyrusFlow {
        switch target {
        case let .function(resolved):
            try pushFrame(
                resolved,
                instanceHandle: call.receiver,
                arguments: call.arguments,
                completion: .assign(destination)
            )
            return .next
        case let .native(script, key):
            return try natives.nativeFlow(
                nativeCall(
                    kind: call.kind, script: (script, key), function: call.function,
                    call: (call.receiver, call.arguments)
                ),
                destination: destination
            )
        }
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
        call: (receiver: PapyrusObjectHandle, arguments: [PapyrusValue]),
        destination: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow? {
        let (receiver, arguments) = call
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
        call: (receiver: PapyrusObjectHandle?, arguments: [PapyrusValue])
    ) -> PapyrusNativeCall {
        let (receiver, arguments) = call
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
        return CallName(
            spelling: spelling, key: keys?.function, scriptKey: keys?.script,
            mayBeStateCall: keys?.isStateCall ?? true
        )
    }

    /// A call on a receiver with no script instance: a Papyrus wrapper of its declared
    /// type runs, anything else goes to native dispatch.
    private func externalTarget(
        _ function: CallName,
        receiverOperand: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusCallTarget {
        if
            let wrapper = try externalWrapper(
                function.spelling,
                receiverOperand: receiverOperand,
                frame: frame
            )
        {
            return .function(wrapper)
        }
        let declared = receiverScriptName(receiverOperand, frame: frame)
        let owner = nativeOwner(of: function.spelling, from: declared)
        return .native(
            script: owner?.script.name ?? declared,
            key: owner?.key ?? runtime.index(named: declared)?.key
        )
    }

    /// A function written in Papyrus on the receiver's declared type, such as
    /// `ObjectReference.IsInInterior`, run on a receiver that has no script of its own.
    /// The declared script loads on first use, as a static call's global script does.
    private func externalWrapper(
        _ functionName: String,
        receiverOperand: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusResolvedFunction? {
        let declared = receiverScriptName(receiverOperand, frame: frame)
        if runtime.index(named: declared) == nil {
            _ = runtime.loadScript?(declared)
        }
        for owner in try runtime.indexChain(from: declared) {
            guard let compiled = owner.function(named: functionName, state: "") else { continue }
            let resolved = PapyrusResolvedFunction(owner: owner, compiled: compiled)
            return resolved.function.flags.contains(.native) ? nil : resolved
        }
        return nil
    }

    /// The script in `declared`'s parent chain that declares `functionName` native, as a
    /// call on an instance resolves it. Nil when no loaded script does.
    private func nativeOwner(
        of functionName: String,
        from declared: String
    ) -> PapyrusScriptIndex? {
        guard let chain = attempt({ try runtime.indexChain(from: declared) }) else { return nil }
        return chain.first { $0.declaresNative(functionName) }
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
    /// False when the folded name shows the call is not `GotoState` or `GetState`.
    let mayBeStateCall: Bool
}

/// One call on its way to a target: what kind it is, its name, and its inputs.
private struct PendingCall {
    let kind: PapyrusNativeCallKind
    let function: CallName
    let receiver: PapyrusObjectHandle?
    let arguments: [PapyrusValue]
}
