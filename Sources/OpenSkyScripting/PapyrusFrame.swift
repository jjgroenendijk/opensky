// One explicitly stacked Papyrus function invocation.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

nonisolated public enum PapyrusFrameCompletion: Sendable {
    case root
    case assign(PexValue)
    case discard
}

nonisolated public final class PapyrusFrame {
    public let ownerScript: PexObject
    public let function: PexFunction
    public let instanceHandle: PapyrusObjectHandle?
    public let completion: PapyrusFrameCompletion

    public private(set) var values: [String: PapyrusValue] = [:]
    public private(set) var types: [String: PapyrusType] = [:]
    public var instructionIndex = 0

    public init(
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

    public var defaultReturnValue: PapyrusValue {
        PapyrusType(name: function.returnTypeName).defaultValue
    }

    public func localValue(named name: String) -> PapyrusValue? {
        values[PapyrusRuntime.key(name)]
    }

    public func localType(named name: String) -> PapyrusType? {
        types[PapyrusRuntime.key(name)]
    }

    public func setLocalValue(_ value: PapyrusValue, named name: String) -> Bool {
        let key = PapyrusRuntime.key(name)
        guard values[key] != nil else {
            return false
        }
        values[key] = value
        return true
    }
}
