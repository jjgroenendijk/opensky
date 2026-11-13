// The calls a reference's scripts wait in, so a stalled script shows where it stopped.

import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime.Timers {
    public func waits(on key: ReferenceKey) -> [PapyrusWaitReadout] {
        world.scheduler.pendingCalls.compactMap { call in
            guard
                let instance = world.suspensionTracker.instance(waiting: call.id),
                instance.reference == key
            else { return nil }
            return PapyrusWaitReadout(
                script: instance.scriptName,
                native: "\(call.nativeCall.scriptName).\(call.nativeCall.functionName)",
                request: String(describing: call.request)
            )
        }
    }
}

extension PapyrusWorldRuntime.Timers {
    /// Live variables, so an object shows the reference it holds; a save keeps none.
    public func instances(on key: ReferenceKey) -> [PapyrusInstanceReadout] {
        let keys = world.instancesByKey.keys.filter { $0.reference == key }.sorted()
        return keys.compactMap { instanceKey in
            guard
                let handle = world.instancesByKey[instanceKey],
                let instance = world.runtime.instance(for: handle)
            else { return nil }
            return PapyrusInstanceReadout(
                script: instanceKey.scriptName,
                state: instance.activeState,
                variables: instance.sortedVariableStates().map {
                    "\($0.name) = \(variableText($0.value))"
                }
            )
        }
    }

    private func variableText(_ value: PapyrusValue) -> String {
        guard case let .object(handle) = value else { return "\(value)" }
        return world.referenceKey(for: handle).map { "object(\($0))" } ?? "\(value)"
    }
}
