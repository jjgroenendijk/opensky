// Mutable state for one attached Papyrus script instance.
//
// Variables are stored per declaring script so a parent and child may each own
// a private variable with the same name. The public initial-values seam is
// unqualified and therefore applies to the first child-to-parent match.

import Foundation

nonisolated final class PapyrusInstance {
    let handle: PapyrusObjectHandle
    let rootScriptName: String
    var activeState: String

    private var variablesByScript: [String: [String: PapyrusValue]]

    init(
        handle: PapyrusObjectHandle,
        rootScriptName: String,
        activeState: String,
        variablesByScript: [String: [String: PapyrusValue]]
    ) {
        self.handle = handle
        self.rootScriptName = rootScriptName
        self.activeState = activeState
        self.variablesByScript = variablesByScript
    }

    func value(named name: String, declaredBy scriptName: String) -> PapyrusValue? {
        variablesByScript[Self.key(scriptName)]?[Self.key(name)]
    }

    func setValue(
        _ value: PapyrusValue,
        named name: String,
        declaredBy scriptName: String
    ) -> Bool {
        let scriptKey = Self.key(scriptName)
        let nameKey = Self.key(name)
        guard variablesByScript[scriptKey]?[nameKey] != nil else {
            return false
        }
        variablesByScript[scriptKey]?[nameKey] = value
        return true
    }

    func applyInitialValue(
        _ value: PapyrusValue,
        named name: String,
        scriptChain: [PexObject]
    ) -> Bool {
        for script in scriptChain
            where setValue(value, named: name, declaredBy: script.name)
        {
            return true
        }
        return false
    }

    static func key(_ value: String) -> String {
        value.lowercased()
    }
}

nonisolated struct PapyrusResolvedFunction {
    let script: PexObject
    let function: PexFunction
}

nonisolated struct PapyrusResolvedProperty {
    let script: PexObject
    let property: PexProperty
}
