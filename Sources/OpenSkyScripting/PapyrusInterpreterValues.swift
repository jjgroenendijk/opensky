// Identifier resolution, assignment, casts, and hierarchy lookup.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

extension PapyrusInterpreter {
    public func read(
        _ operand: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusValue {
        switch operand {
        case .null:
            .none
        case let .string(value):
            .string(value)
        case let .integer(value):
            .integer(value)
        case let .float(value):
            .float(value)
        case let .boolean(value):
            .boolean(value)
        case let .identifier(name):
            try readIdentifier(name, frame: frame)
        }
    }

    public func write(
        _ value: PapyrusValue,
        to destination: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) {
        guard case let .identifier(name) = destination else {
            if destination == .null {
                return
            }
            throw .invalidOperand(
                instruction: instructionIndex,
                detail: "destination is not an identifier"
            )
        }
        let binding = frame.compiled.binding(for: name)
        if binding.isDiscard {
            return
        }
        if let slot = binding.slot {
            try frame.setSlot(slot, to: cast(value, to: frame.compiled.slotTypes[slot]))
            return
        }
        if
            let instance = frame.instanceHandle.flatMap(runtime.instance(for:)),
            let declared = try declaredVariable(name, frame: frame)
        {
            let converted = try cast(value, to: PapyrusType(name: declared.variable.typeName))
            _ = instance.setValue(
                converted, named: declared.variable.name, declaredBy: declared.owner.name
            )
            return
        }
        throw .invalidOperand(
            instruction: instructionIndex,
            detail: "unknown destination \(name)"
        )
    }

    public func destinationType(
        _ destination: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusType {
        guard case let .identifier(name) = destination else {
            throw .invalidOperand(
                instruction: instructionIndex,
                detail: "destination is not an identifier"
            )
        }
        if let slot = frame.compiled.binding(for: name).slot {
            return frame.compiled.slotTypes[slot]
        }
        if let declared = try declaredVariable(name, frame: frame) {
            return PapyrusType(name: declared.variable.typeName)
        }
        throw .invalidOperand(
            instruction: instructionIndex,
            detail: "unknown destination \(name)"
        )
    }

    public func cast(
        _ value: PapyrusValue,
        to type: PapyrusType
    ) throws(PapyrusFault) -> PapyrusValue {
        do {
            switch type {
            case .none:
                guard value == .none else {
                    throw PapyrusCoercionError.unsupported(
                        source: value.typeName, destination: type.name
                    )
                }
                return .none
            case .boolean:
                return .boolean(runtime.coercion.toBoolean(value))
            case .integer:
                return try .integer(runtime.coercion.toInteger(value))
            case .float:
                return try .float(runtime.coercion.toFloat(value))
            case .string:
                return .string(runtime.coercion.toString(value))
            case .object, .array:
                return try castReference(value, to: type)
            }
        } catch {
            throw .typeMismatch(
                instruction: instructionIndex,
                expected: type.name,
                actual: value.typeName
            )
        }
    }

    private func castReference(
        _ value: PapyrusValue,
        to type: PapyrusType
    ) throws(PapyrusCoercionError) -> PapyrusValue {
        if value == .none {
            return .none
        }
        switch (value, type) {
        case let (.object(handle), .object(name)):
            if runtime.instance(for: handle) != nil, runtime.resolvesObject(handle, as: name) {
                return value
            }
            if let sibling = runtime.siblingInstance?(handle, name) {
                return .object(sibling)
            }
            // A form that is not of the type casts to None (CK wiki "Cast Reference").
            return runtime.instance(for: handle) == nil ? value : .none
        case let (.array(array), .array(elementType))
            where array.elementType == elementType:
            return value
        default:
            throw .unsupported(source: value.typeName, destination: type.name)
        }
    }

    public func declaredType(
        of operand: PexValue,
        frame: PapyrusFrame
    ) -> PapyrusType? {
        guard case let .identifier(name) = operand else {
            return nil
        }
        let binding = frame.compiled.binding(for: name)
        if binding.isSelf {
            return .object(frame.ownerScript.name)
        }
        if let slot = binding.slot {
            return frame.compiled.slotTypes[slot]
        }
        let declared = try? declaredVariable(name, frame: frame)
        return declared.map { PapyrusType(name: $0.variable.typeName) }
    }

    public func resolveMethod(
        _ name: String,
        instance: PapyrusInstance,
        startingAt scriptName: String? = nil
    ) throws(PapyrusFault) -> PapyrusResolvedFunction? {
        let chain = try runtime.indexChain(from: scriptName ?? instance.rootScriptName)
        for state in [instance.activeState, ""] {
            for owner in chain {
                if let compiled = owner.function(named: name, state: state) {
                    return PapyrusResolvedFunction(owner: owner, compiled: compiled)
                }
            }
        }
        return nil
    }

    public func resolveProperty(
        _ name: String,
        instance: PapyrusInstance
    ) throws(PapyrusFault) -> PapyrusResolvedProperty? {
        for script in try runtime.scriptChain(from: instance.rootScriptName) {
            if
                let property = script.properties.first(where: {
                    PapyrusRuntime.matches($0.name, name)
                })
            {
                return PapyrusResolvedProperty(script: script, property: property)
            }
        }
        return nil
    }

    /// The empty-state function `name` of the library script `script`.
    public func staticFunction(_ name: String, script: String) -> PapyrusResolvedFunction? {
        guard
            let owner = runtime.index(named: script),
            let compiled = owner.function(named: name, state: "")
        else { return nil }
        return PapyrusResolvedFunction(owner: owner, compiled: compiled)
    }

    public func propertyHandler(
        of resolved: PapyrusResolvedProperty,
        writing: Bool
    ) -> PapyrusResolvedFunction? {
        guard
            let owner = runtime.index(named: resolved.script.name),
            let compiled = owner.handler(ofProperty: resolved.property.name, writing: writing)
        else { return nil }
        return PapyrusResolvedFunction(owner: owner, compiled: compiled)
    }

    private func readIdentifier(
        _ name: String,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusValue {
        let binding = frame.compiled.binding(for: name)
        if binding.isDiscard {
            return .none
        }
        if binding.isSelf {
            return frame.instanceHandle.map(PapyrusValue.object) ?? .none
        }
        if let slot = binding.slot {
            return frame.slots[slot]
        }
        if let instance = frame.instanceHandle.flatMap(runtime.instance(for:)) {
            let owner = try declaredVariable(name, frame: frame)?.owner.name ?? frame.ownerScript
                .name
            if let value = instance.value(named: name, declaredBy: owner) {
                return value
            }
        }
        throw .invalidOperand(
            instruction: instructionIndex,
            detail: "unknown identifier \(name)"
        )
    }

    /// Shipped child scripts name variables their parent declares (`PressurePlate`
    /// writes `TrapTriggerBase`'s `::Type_var`), so lookup walks up the chain.
    private func declaredVariable(
        _ name: String,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusScriptIndex.DeclaredVariable? {
        try frame.owner.declaredVariable(name, generation: runtime.scriptsGeneration) {
            () throws(PapyrusFault) in
            try runtime.scriptChain(from: frame.ownerScript.parentClassName)
        }
    }
}
