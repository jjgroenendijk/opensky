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

nonisolated public final class PapyrusCompiledFunction: Sendable {
    public let function: PexFunction
    public let slotTypes: [PapyrusType]
    /// Each slot's starting value, the default of its type.
    public let slotDefaults: [PapyrusValue]
    /// The slot each argument fills. Nil when a later declaration of the same name hides
    /// the parameter, because that declaration's value wins.
    public let argumentSlots: [Int?]
    public let defaultReturnValue: PapyrusValue

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
