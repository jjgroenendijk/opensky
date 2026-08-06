// Identifier resolution, assignment, casts, and hierarchy lookup.

import Foundation

nonisolated extension PapyrusInterpreter {
    func read(_ operand: PexValue, frame: PapyrusFrame) throws(PapyrusFault) -> PapyrusValue {
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

    func write(
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
        if Self.isDiscard(name) {
            return
        }
        if let type = frame.localType(named: name) {
            _ = try frame.setLocalValue(cast(value, to: type), named: name)
            return
        }
        if
            let instance = frame.instanceHandle.flatMap(runtime.instance(for:)),
            let variable = frame.ownerScript.variables.first(where: {
                PapyrusRuntime.matches($0.name, name)
            })
        {
            let converted = try cast(value, to: PapyrusType(name: variable.typeName))
            _ = instance.setValue(
                converted, named: variable.name, declaredBy: frame.ownerScript.name
            )
            return
        }
        throw .invalidOperand(
            instruction: instructionIndex,
            detail: "unknown destination \(name)"
        )
    }

    func destinationType(
        _ destination: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusType {
        guard case let .identifier(name) = destination else {
            throw .invalidOperand(
                instruction: instructionIndex,
                detail: "destination is not an identifier"
            )
        }
        if let type = frame.localType(named: name) {
            return type
        }
        if
            let variable = frame.ownerScript.variables.first(where: {
                PapyrusRuntime.matches($0.name, name)
            })
        {
            return PapyrusType(name: variable.typeName)
        }
        throw .invalidOperand(
            instruction: instructionIndex,
            detail: "unknown destination \(name)"
        )
    }

    func cast(_ value: PapyrusValue, to type: PapyrusType) throws(PapyrusFault) -> PapyrusValue {
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
            if runtime.instance(for: handle) == nil || runtime.resolvesObject(handle, as: name) {
                return value
            }
        case let (.array(array), .array(elementType))
            where array.elementType == elementType:
            return value
        default:
            throw .unsupported(source: value.typeName, destination: type.name)
        }
        throw .unsupported(source: value.typeName, destination: type.name)
    }

    func declaredType(
        of operand: PexValue,
        frame: PapyrusFrame
    ) -> PapyrusType? {
        guard case let .identifier(name) = operand else {
            return nil
        }
        if PapyrusRuntime.matches(name, "self") || PapyrusRuntime.matches(name, "_self") {
            return .object(frame.ownerScript.name)
        }
        if let type = frame.localType(named: name) {
            return type
        }
        return frame.ownerScript.variables.first(where: {
            PapyrusRuntime.matches($0.name, name)
        }).map { PapyrusType(name: $0.typeName) }
    }

    func resolveMethod(
        _ name: String,
        instance: PapyrusInstance,
        startingAt scriptName: String? = nil
    ) throws(PapyrusFault) -> PapyrusResolvedFunction? {
        let start = scriptName ?? instance.rootScriptName
        let chain = try runtime.scriptChain(from: start)
        for script in chain {
            if let function = function(named: name, state: instance.activeState, script: script) {
                return PapyrusResolvedFunction(script: script, function: function)
            }
        }
        for script in chain {
            if let function = function(named: name, state: "", script: script) {
                return PapyrusResolvedFunction(script: script, function: function)
            }
        }
        return nil
    }

    func resolveProperty(
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

    func function(named name: String, state: String, script: PexObject) -> PexFunction? {
        script.states.first(where: { PapyrusRuntime.matches($0.name, state) })?
            .functions.first(where: { PapyrusRuntime.matches($0.name, name) })?
            .function
    }

    private func readIdentifier(
        _ name: String,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusValue {
        if Self.isDiscard(name) {
            return .none
        }
        if PapyrusRuntime.matches(name, "self") || PapyrusRuntime.matches(name, "_self") {
            return frame.instanceHandle.map(PapyrusValue.object) ?? .none
        }
        if let value = frame.localValue(named: name) {
            return value
        }
        if
            let instance = frame.instanceHandle.flatMap(runtime.instance(for:)),
            let value = instance.value(named: name, declaredBy: frame.ownerScript.name)
        {
            return value
        }
        throw .invalidOperand(
            instruction: instructionIndex,
            detail: "unknown identifier \(name)"
        )
    }

    private static func isDiscard(_ name: String) -> Bool {
        let key = PapyrusRuntime.key(name)
        return key == "::nonevar" || key == "none"
    }
}
