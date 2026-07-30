// Save-state seam for `PapyrusWorldRuntime` (issue #171 stage A). Stage B
// serializes `PapyrusInstanceState` into the `PSCR` chunk; this file only
// snapshots and restores it.

import Foundation

extension PapyrusWorldRuntime {
    /// Every live instance's persisted state, sorted by `PapyrusInstanceKey`
    /// so the output is byte-deterministic input for a save encoder.
    ///
    /// `PapyrusValue.object` and `.array` are not persistable (their identity
    /// is runtime-allocated with no world meaning) and snapshot as `.none`.
    func instanceStates() -> [PapyrusInstanceState] {
        instancesByKey.keys.sorted().compactMap { key in
            guard
                let handle = instancesByKey[key],
                let instance = runtime.instance(for: handle)
            else {
                return nil
            }
            return PapyrusInstanceState(
                key: key,
                activeState: instance.activeState,
                variables: instance.sortedVariableStates().map(Self.persistable),
                hasFiredOnInit: firedOnInit.contains(key)
            )
        }
    }

    /// Rebuilds instance state from a save. Tolerant by design: an unknown
    /// script name or variable name is skipped and counted, never a fault.
    /// Restoring into a fresh runtime that has attached no cell yet works —
    /// missing instances are created from the script library on demand — and
    /// the `OnInit`-fired set is repopulated from `hasFiredOnInit`.
    func restore(instanceStates: [PapyrusInstanceState]) {
        for state in instanceStates {
            restoreInstance(state)
        }
    }

    private func restoreInstance(_ state: PapyrusInstanceState) {
        guard
            let handle = existingOrCreatedHandle(for: state.key),
            let instance = runtime.instance(for: handle)
        else {
            skips.note(.unknownSaveScript)
            return
        }
        instance.activeState = state.activeState
        for variable in state.variables where !instance.restore(variable) {
            skips.note(.unknownSaveVariable)
        }
        if state.hasFiredOnInit {
            firedOnInit.insert(state.key)
        } else {
            firedOnInit.remove(state.key)
        }
    }

    private func existingOrCreatedHandle(
        for key: PapyrusInstanceKey
    ) -> PapyrusObjectHandle? {
        if let handle = instancesByKey[key] {
            return handle
        }
        guard
            let handle = try? runtime.makeInstance(scriptName: key.scriptName)
        else {
            return nil
        }
        instancesByKey[key] = handle
        keysByHandle[handle] = key
        return handle
    }

    private static func persistable(
        _ state: PapyrusVariableState
    ) -> PapyrusVariableState {
        switch state.value {
        case .object, .array:
            PapyrusVariableState(
                declaringScript: state.declaringScript,
                name: state.name,
                value: .none
            )
        default:
            state
        }
    }
}
