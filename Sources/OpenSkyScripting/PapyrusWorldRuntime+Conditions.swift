// The script-variable seam `GetVMQuestVariable` and `GetVMScriptVariable` read.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// The number variables of every live instance, by the object it is attached to.
    public func scriptVariableResolution() -> ScriptVariableResolution {
        var values: [ReferenceKey: [String: Float]] = [:]
        for (key, handle) in instancesByKey {
            guard let instance = runtime.instance(for: handle) else { continue }
            instance.numericVariables(into: &values[key.reference, default: [:]])
        }
        return ScriptVariableResolution(values: values)
    }
}
