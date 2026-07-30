// One explicitly stacked Papyrus function invocation.

import Foundation

nonisolated enum PapyrusFrameCompletion {
    case root
    case assign(PexValue)
    case discard
}

nonisolated final class PapyrusFrame {
    let ownerScript: PexObject
    let function: PexFunction
    let instanceHandle: PapyrusObjectHandle?
    let completion: PapyrusFrameCompletion

    private(set) var values: [String: PapyrusValue] = [:]
    private(set) var types: [String: PapyrusType] = [:]
    var instructionIndex = 0

    init(
        ownerScript: PexObject,
        function: PexFunction,
        instanceHandle: PapyrusObjectHandle?,
        arguments: [PapyrusValue],
        completion: PapyrusFrameCompletion
    ) {
        self.ownerScript = ownerScript
        self.function = function
        self.instanceHandle = instanceHandle
        self.completion = completion
        for (index, parameter) in function.parameters.enumerated() {
            let key = PapyrusRuntime.key(parameter.name)
            let type = PapyrusType(name: parameter.typeName)
            types[key] = type
            values[key] = arguments.indices.contains(index)
                ? arguments[index]
                : type.defaultValue
        }
        for local in function.localVariables {
            let key = PapyrusRuntime.key(local.name)
            let type = PapyrusType(name: local.typeName)
            types[key] = type
            values[key] = type.defaultValue
        }
    }

    var defaultReturnValue: PapyrusValue {
        PapyrusType(name: function.returnTypeName).defaultValue
    }

    func localValue(named name: String) -> PapyrusValue? {
        values[PapyrusRuntime.key(name)]
    }

    func localType(named name: String) -> PapyrusType? {
        types[PapyrusRuntime.key(name)]
    }

    func setLocalValue(_ value: PapyrusValue, named name: String) -> Bool {
        let key = PapyrusRuntime.key(name)
        guard values[key] != nil else {
            return false
        }
        values[key] = value
        return true
    }
}
