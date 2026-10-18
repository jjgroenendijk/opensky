// A PEX function with its parameter and local names resolved to slots once, when its
// script is indexed, so the interpreter reads a local without folding its name.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

/// What one identifier spelling names inside a function.
nonisolated public struct PapyrusNameBinding: Equatable, Sendable {
    /// `::NoneVar` or `None`: a read gives `None` and a write is dropped.
    public let isDiscard: Bool
    /// `self` or `_self`.
    public let isSelf: Bool
    /// The parameter or local slot the name stands for.
    public let slot: Int?
}

/// The names one call instruction names, folded when the script is indexed.
nonisolated public struct PapyrusCallNameKeys: Equatable, Sendable {
    public let functionSpelling: String
    public let function: String
    /// The script a static call names; nil for a method or parent call.
    public let script: String?
}

nonisolated public final class PapyrusCompiledFunction: Sendable {
    public let function: PexFunction
    public let slotTypes: [PapyrusType]
    /// Each slot's starting value, the default of its type.
    public let slotDefaults: [PapyrusValue]
    /// The slot each argument fills. Nil when a later declaration of the same name hides
    /// the parameter, because that declaration's value wins.
    public let argumentSlots: [Int?]
    public let defaultReturnValue: PapyrusValue
    /// One entry per instruction; nil for an instruction that is not a call.
    public let callNameKeys: [PapyrusCallNameKeys?]

    private let slotsByKey: [String: Int]
    /// Every identifier spelling the instructions use, so the run loop never folds one.
    private let bindingsBySpelling: [String: PapyrusNameBinding]

    public init(_ function: PexFunction) {
        self.function = function
        let declarations = function.parameters + function.localVariables
        var slotsByKey: [String: Int] = [:]
        var types: [PapyrusType] = []
        var declarationSlots: [Int] = []
        for declaration in declarations {
            let key = PapyrusName.key(declaration.name)
            let type = PapyrusType(name: declaration.typeName)
            if let slot = slotsByKey[key] {
                types[slot] = type
                declarationSlots.append(slot)
            } else {
                slotsByKey[key] = types.count
                declarationSlots.append(types.count)
                types.append(type)
            }
        }
        argumentSlots = function.parameters.indices.map { index in
            let slot = declarationSlots[index]
            return declarationSlots[(index + 1)...].contains(slot) ? nil : slot
        }
        slotTypes = types
        slotDefaults = types.map(\.defaultValue)
        defaultReturnValue = PapyrusType(name: function.returnTypeName).defaultValue
        self.slotsByKey = slotsByKey
        var bindings: [String: PapyrusNameBinding] = [:]
        for instruction in function.instructions {
            for case let .identifier(name) in instruction.operands where bindings[name] == nil {
                bindings[name] = Self.binding(name, slotsByKey: slotsByKey)
            }
        }
        bindingsBySpelling = bindings
        callNameKeys = function.instructions.map(Self.callNameKeys)
    }

    /// The folded names of the call at `index`, when its function is spelled `spelling`.
    public func callNameKeys(at index: Int, spelling: String) -> PapyrusCallNameKeys? {
        guard callNameKeys.indices.contains(index), let keys = callNameKeys[index] else {
            return nil
        }
        return keys.functionSpelling == spelling ? keys : nil
    }

    private static func callNameKeys(_ instruction: PexInstruction) -> PapyrusCallNameKeys? {
        let operands = instruction.operands
        switch instruction.opcode {
        case .callMethod, .callParent:
            guard let function = operands.first?.stringValue else { return nil }
            return PapyrusCallNameKeys(
                functionSpelling: function, function: PapyrusName.key(function), script: nil
            )
        case .callStatic:
            guard
                operands.count > 1,
                let script = operands[0].stringValue,
                let function = operands[1].stringValue
            else { return nil }
            return PapyrusCallNameKeys(
                functionSpelling: function,
                function: PapyrusName.key(function),
                script: PapyrusName.key(script)
            )
        default:
            return nil
        }
    }

    public func binding(for name: String) -> PapyrusNameBinding {
        bindingsBySpelling[name] ?? Self.binding(name, slotsByKey: slotsByKey)
    }

    private static func binding(
        _ name: String,
        slotsByKey: [String: Int]
    ) -> PapyrusNameBinding {
        let key = PapyrusName.key(name)
        return PapyrusNameBinding(
            isDiscard: key == "::nonevar" || key == "none",
            isSelf: key == "self" || key == "_self",
            slot: slotsByKey[key]
        )
    }
}
