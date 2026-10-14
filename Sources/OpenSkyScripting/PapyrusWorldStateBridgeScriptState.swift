// Reads and writes of `ScriptedReferenceState`, the flags and links a script set on a
// form that no other runtime holds. See docs/engine/papyrus-script-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge {
    public func scriptedState(of key: ReferenceKey) -> ScriptedReferenceState {
        worldState.component(ScriptedReferenceState.self, for: key) ?? ScriptedReferenceState()
    }

    /// Every form's script state, for the conditions. Rebuilt only after a state write.
    public func scriptedStateResolution() -> ScriptedStateConditionResolution {
        let store = worldState
        return store.derived(ScriptedStateConditionResolution.self, from: self) {
            var states: [ReferenceKey: ScriptedReferenceState] = [:]
            for key in store.sortedDirtyKeys() {
                states[key] = store.component(ScriptedReferenceState.self, for: key)
            }
            return ScriptedStateConditionResolution(states: states)
        }
    }

    /// Records what a member of `faction` makes of a member of `other`, then hands every
    /// scripted reaction to the faction runtime.
    public func setFactionReaction(
        _ reaction: ActorReaction, of faction: ReferenceKey, toward other: ReferenceKey
    ) {
        let name = Self.factionReactionPrefix + "\(other)"
        updateScriptedState(of: faction) { state in
            state.setForm(name, other)
            state.setValue(name, Float(reaction.rawValue))
        }
        publishFactionReactions()
    }

    /// Hands the stored reactions to `factionReactionsChanged`, also after a load.
    public func publishFactionReactions() {
        factionReactionsChanged?(scriptedFactionReactions())
    }

    public func scriptedFactionReactions() -> [FactionReactionOverride] {
        var reactions: [FactionReactionOverride] = []
        for key in worldState.sortedDirtyKeys() {
            guard let state = worldState.component(ScriptedReferenceState.self, for: key) else {
                continue
            }
            for (name, other) in state.forms.sorted(by: { $0.key < $1.key })
                where name.hasPrefix(Self.factionReactionPrefix)
            {
                guard
                    let raw = state.value(name).flatMap({ UInt8(exactly: $0) }),
                    let reaction = ActorReaction(rawValue: raw)
                else { continue }
                reactions.append(FactionReactionOverride(
                    from: key,
                    toward: other,
                    reaction: reaction
                ))
            }
        }
        return reactions
    }

    private static let factionReactionPrefix = "factionreaction:"

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
