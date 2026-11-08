// The calls a reference's scripts wait in, so a stalled script shows where it stopped.

public import OpenSkyFormatsESM
public import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    public func waits(on key: ReferenceKey) -> [PapyrusWaitReadout] {
        scheduler.pendingCalls.compactMap { call in
            guard
                let instance = suspensionTracker.instance(waiting: call.id),
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

extension PapyrusWorldRuntime {
    /// Live variables, so an object shows the reference it holds; a save keeps none.
    public func instances(on key: ReferenceKey) -> [PapyrusInstanceReadout] {
        let keys = instancesByKey.keys.filter { $0.reference == key }.sorted()
        return keys.compactMap { instanceKey in
            guard
                let handle = instancesByKey[instanceKey],
                let instance = runtime.instance(for: handle)
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
        return referenceKey(for: handle).map { "object(\($0))" } ?? "\(value)"
    }
}
