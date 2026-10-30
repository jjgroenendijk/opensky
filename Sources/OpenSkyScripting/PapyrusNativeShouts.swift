// Words of power and shouts a script gives or takes
// (<https://ck.uesp.net/wiki/Game_Script>, <https://ck.uesp.net/wiki/Actor_Script>).
// They record what an actor knows and wears in the script state, which the shout
// runtime reads. See docs/engine/papyrus-script-state.md and docs/engine/shouts.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installShouts(into registry: inout PapyrusNativeRegistry) {
        // `TeachWord(WordOfPower)` and `UnlockWord(WordOfPower)` act on the player.
        let names: [(String, @Sendable (ReferenceKey) -> String)] = [
            ("TeachWord", ScriptedStateName.wordKnown), (
                "UnlockWord",
                ScriptedStateName.wordUnlocked
            )
        ]
        for (name, flag) in names {
            withForm("Game", name, into: &registry) { _, bridge, player, word in
                let known = bridge.scriptedState(of: player).flag(flag(word)) == true
                bridge.updateScriptedState(of: player) { $0.setFlag(flag(word), true) }
                if name == "TeachWord", !known, let text = bridge.formName(of: word) {
                    bridge.presenter?.postWorldNotice(.wordLearned(word: text))
                }
                return .returned(.none)
            }
        }
        withForm("Game", "IsWordUnlocked", into: &registry) { _, bridge, player, word in
            let state = bridge.scriptedState(of: player)
            return .returned(.boolean(state.flag(ScriptedStateName.wordUnlocked(word)) == true))
        }
        withForm("Actor", "AddShout", into: &registry) { _, bridge, actor, shout in
            bridge
                .updateScriptedState(of: actor) { $0.setFlag(ScriptedStateName.shout(shout), true) }
            return .returned(.none)
        }
        // `bool RemoveShout(Shout)`: true when the actor knew it. An equipped shout goes too.
        withForm("Actor", "RemoveShout", into: &registry) { _, bridge, actor, shout in
            let knew = bridge.scriptedState(of: actor).flag(ScriptedStateName.shout(shout)) == true
            bridge.updateScriptedState(of: actor) { state in
                state.setFlag(ScriptedStateName.shout(shout), nil)
                if state.form(equippedShoutName) == shout {
                    state.setForm(equippedShoutName, nil)
                }
            }
            return .returned(.boolean(knew))
        }
        withForm("Actor", "EquipShout", into: &registry) { _, bridge, actor, shout in
            bridge.updateScriptedState(of: actor) { $0.setForm(equippedShoutName, shout) }
            return .returned(.none)
        }
        withForm("Actor", "UnequipShout", into: &registry) { _, bridge, actor, shout in
            bridge.updateScriptedState(of: actor) { state in
                if state.form(equippedShoutName) == shout {
                    state.setForm(equippedShoutName, nil)
                }
            }
            return .returned(.none)
        }
        scriptState("Actor", "GetEquippedShout", into: &registry) { _, bridge, actor in
            let shout = bridge.scriptedState(of: actor).form(equippedShoutName)
            return .returned(shout.map { handle($0, in: bridge) } ?? .none)
        }
    }

    static let equippedShoutName = ScriptedStateName.equippedShout

    /// A native on the receiver's script state (the player's for `Game`) whose argument
    /// 0 is a form.
    private static func withForm(
        _ script: String, _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, ReferenceKey, ReferenceKey
        ) -> PapyrusNativeResult
    ) {
        scriptState(script, name, into: &registry) { call, bridge, key in
            guard let form = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)) else {
                return failure(call, "\(name) needs a form")
            }
            return body(call, bridge, key, form)
        }
    }
}
