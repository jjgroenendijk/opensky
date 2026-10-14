// Reads and writes of `ScriptedReferenceState`, the flags and links a script set on a
// form that no other runtime holds. See docs/engine/papyrus-script-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge {
    public func scriptedState(of key: ReferenceKey) -> ScriptedReferenceState {
        worldState.component(ScriptedReferenceState.self, for: key) ?? ScriptedReferenceState()
    }

    /// Applies `change` to the state of `key`. An empty result is stored as no component.
    public func updateScriptedState(
        of key: ReferenceKey, _ change: (inout ScriptedReferenceState) -> Void
    ) {
        var state = scriptedState(of: key)
        change(&state)
        if state.isEmpty {
            worldState.reset(.scriptedState, for: key)
        } else {
            worldState.set(state, for: key, in: cellLocation(of: key))
        }
    }

    /// The plugin entries of a form list, then the forms a script added with `AddForm`.
    public func formListEntries(of key: ReferenceKey) -> [ReferenceKey?]? {
        let added = scriptedState(of: key).addedForms.map { Optional($0) }
        guard let entries = pluginFormListEntries(of: key) else {
            return added.isEmpty ? nil : added
        }
        return entries + added
    }

    func isActivationBlocked(_ key: ReferenceKey) -> Bool {
        scriptedState(of: key).flag(PapyrusNativeFunctions.activationBlockedName) == true
    }
}
