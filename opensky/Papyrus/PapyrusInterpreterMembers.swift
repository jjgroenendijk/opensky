// PEX property access opcodes.

import Foundation

nonisolated extension PapyrusInterpreter {
    func memberOp(
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
        let instance = try propertyInstance(operands[1], frame: frame)
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
        let instance = try propertyInstance(operands[1], frame: frame)
        let value = try read(operands[2], frame: frame)
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

    private func propertyInstance(
        _ operand: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusInstance {
        let value = try read(operand, frame: frame)
        guard case let .object(handle) = value else {
            throw .typeMismatch(
                instruction: instructionIndex,
                expected: "Object",
                actual: value.typeName
            )
        }
        guard let instance = runtime.instance(for: handle) else {
            throw .missingInstance(handle)
        }
        return instance
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
