// The script-variable seam `GetVMQuestVariable` and `GetVMScriptVariable` read.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// The number variables of every live instance, by the object it is attached to.
    /// Contexts are built far more often than variables change, so the snapshot is
    /// kept until a variable or the instance set changes.
    public func scriptVariableResolution() -> ScriptVariableResolution {
        let generation = runtime.variableGeneration.value
        if let cachedScriptVariables, cachedScriptVariables.generation == generation {
            return cachedScriptVariables.resolution
        }
        var values: [ReferenceKey: [String: Float]] = [:]
        for (key, handle) in instancesByKey {
            guard let instance = runtime.instance(for: handle) else { continue }
            instance.numericVariables(into: &values[key.reference, default: [:]])
        }
        let resolution = ScriptVariableResolution(values: values)
        cachedScriptVariables = (generation, resolution)
        return resolution
    }
}
