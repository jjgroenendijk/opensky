// PEX property access opcodes.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

extension PapyrusInterpreter {
    public func memberOp(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow? {
        switch instruction.opcode {
        case .propertyGet:
            try propertyGet(instruction, frame: frame)
        case .propertySet:
            try propertySet(instruction, frame: frame)
        default:
            nil
        }
    }

    private func propertyGet(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(3, instruction: instruction)
        let propertyName = try propertyName(operands[0])
        if
            let flow = try instancelessAccess(
                propertyName, receiver: operands[1], setting: nil, destination: operands[2],
                frame: frame
            )
        {
            return flow
        }
        guard let instance = try propertyInstance(operands[1], frame: frame) else {
            try write(nativeReturnType(operands[2]).defaultValue, to: operands[2], frame: frame)
            return .next
        }
        guard let resolved = try resolveProperty(propertyName, instance: instance) else {
            throw .missingProperty(
                instruction: instructionIndex,
                script: instance.rootScriptName,
                property: propertyName
            )
        }
        if resolved.property.flags.contains(.automatic) {
            guard
                let variableName = resolved.property.automaticVariableName,
                let value = instance.value(
                    named: variableName,
                    declaredBy: resolved.script.name
                )
            else {
                throw .invalidOperand(
                    instruction: instructionIndex,
                    detail: "automatic property \(propertyName) has no backing variable"
                )
            }
            try write(value, to: operands[2], frame: frame)
            return .next
        }
        guard let getter = resolved.property.readHandler else {
            throw .missingProperty(
                instruction: instructionIndex,
                script: resolved.script.name,
                property: propertyName
            )
        }
        try pushFrame(
            PapyrusResolvedFunction(script: resolved.script, function: getter),
            instanceHandle: instance.handle,
            arguments: [],
            completion: .assign(operands[2])
        )
        return .next
    }

    private func propertySet(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(3, instruction: instruction)
        let propertyName = try propertyName(operands[0])
        let value = try read(operands[2], frame: frame)
        if
            let flow = try instancelessAccess(
                propertyName, receiver: operands[1], setting: value,
                destination: .identifier("::NoneVar"), frame: frame
            )
        {
            return flow
        }
        guard let instance = try propertyInstance(operands[1], frame: frame) else { return .next }
        guard let resolved = try resolveProperty(propertyName, instance: instance) else {
            throw .missingProperty(
                instruction: instructionIndex,
                script: instance.rootScriptName,
                property: propertyName
            )
        }
        if resolved.property.flags.contains(.automatic) {
            guard let variableName = resolved.property.automaticVariableName else {
                throw .invalidOperand(
                    instruction: instructionIndex,
                    detail: "automatic property \(propertyName) has no backing variable"
                )
            }
            let converted = try cast(value, to: PapyrusType(name: resolved.property.typeName))
            guard
                instance.setValue(
                    converted,
                    named: variableName,
                    declaredBy: resolved.script.name
                )
            else {
                throw .invalidOperand(
                    instruction: instructionIndex,
                    detail: "automatic property \(propertyName) backing variable is missing"
                )
            }
            return .next
        }
        guard let setter = resolved.property.writeHandler else {
            throw .missingProperty(
                instruction: instructionIndex,
                script: resolved.script.name,
                property: propertyName
            )
        }
        try pushFrame(
            PapyrusResolvedFunction(script: resolved.script, function: setter),
            instanceHandle: instance.handle,
            arguments: [value],
            completion: .discard
        )
        return .next
    }

    /// A property on `None` reads as its default and ignores a write, as the game logs
    /// the access and goes on.
    /// A form with several scripts maps to one instance. A member used through a typed
    /// variable belongs to the script of that type, so it goes to that sibling.
    func declaredReceiver(
        _ handle: PapyrusObjectHandle,
        operand: PexValue,
        frame: PapyrusFrame
    ) -> PapyrusObjectHandle {
        guard
            runtime.instance(for: handle) != nil,
            case let .object(typeName) = declaredType(of: operand, frame: frame),
            !runtime.resolvesObject(handle, as: typeName),
            let sibling = runtime.siblingInstance?(handle, typeName)
        else { return handle }
        return sibling
    }

    private func propertyInstance(
        _ operand: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusInstance? {
        let value = try read(operand, frame: frame)
        if value == .none {
            runtime.tally.noteNoneReceiver()
            return nil
        }
        guard case let .object(handle) = value else {
            throw .typeMismatch(
                instruction: instructionIndex,
                expected: "Object",
                actual: value.typeName
            )
        }
        if
            let instance = runtime.instance(for: declaredReceiver(
                handle,
                operand: operand,
                frame: frame
            ))
        {
            return instance
        }
        // A stopped quest's scripts attach on first use (`siblingInstance`).
        guard
            case let .object(typeName) = declaredType(of: operand, frame: frame),
            let sibling = runtime.siblingInstance?(handle, typeName),
            let instance = runtime.instance(for: sibling)
        else {
            throw .missingInstance(handle)
        }
        return instance
    }

    /// A form without a script instance, such as a cart or a global, still has the
    /// properties of its declared type. `Motion_Keyframed` is a getter of `ObjectReference`
    /// that returns 4; `GlobalVariable.Value` has a getter and a setter. Nil `setting` reads.
    private func instancelessAccess(
        _ name: String,
        receiver operand: PexValue,
        setting value: PapyrusValue?,
        destination: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow? {
        guard
            case let .object(handle) = try read(operand, frame: frame),
            runtime.instance(for: handle) == nil,
            case let .object(typeName) = declaredType(of: operand, frame: frame),
            runtime.siblingInstance?(handle, typeName) == nil
        else { return nil }
        for script in try runtime.scriptChain(from: typeName) {
            guard
                let property = script.properties
                    .first(where: { PapyrusRuntime.matches($0.name, name) })
            else { continue }
            let handler = value == nil ? property.readHandler : property.writeHandler
            guard let handler, !property.flags.contains(.automatic) else { return nil }
            try pushFrame(
                PapyrusResolvedFunction(script: script, function: handler),
                instanceHandle: handle,
                arguments: value.map { [$0] } ?? [],
                completion: value == nil ? .assign(destination) : .discard
            )
            return .next
        }
        return nil
    }

    private func propertyName(_ operand: PexValue) throws(PapyrusFault) -> String {
        guard let name = operand.stringValue else {
            throw .invalidOperand(
                instruction: instructionIndex,
                detail: "property name is not a string-table value"
            )
        }
        return name
    }
}
