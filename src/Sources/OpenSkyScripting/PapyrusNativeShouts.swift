// Words of power and shouts a script gives or takes
// (<https://ck.uesp.net/wiki/Game_Script>, <https://ck.uesp.net/wiki/Actor_Script>).
// They record what an actor knows and wears in the script state, which the shout
// runtime reads. See docs/engine/papyrus-script-state.md and docs/engine/shouts.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions.ShoutsNatives {
    public static func installShouts(into registry: inout PapyrusNativeRegistry) {
        installWords(into: &registry)
        // The player getting a shout it did not know sends `NVPE`
        // (docs/engine/story-manager.md#which-events-the-game-sends).
        withForm("Actor", "AddShout", into: &registry) { _, bridge, actor, shout in
            let fromRecord = bridge.scriptState.recordShouts(of: actor).contains(shout)
            let knew = bridge.scriptState.knowsShout(shout, actor: actor, fromRecord: fromRecord)
            bridge.updateScriptedState(of: actor) {
                $0.setFlag(ScriptedStateName.shout(shout), true)
            }
            if actor == bridge.playerKey, !knew {
                _ = bridge.ports.story?.sendStoryEvent(
                    .newVoicePower(actor: actor, power: StoryEventData.form(of: shout))
                )
            }
            return .returned(.none)
        }
        // `bool RemoveShout(Shout)`: true when the actor knew it, from a script or its
        // record. A record shout keeps false, so it stays gone. An equipped shout goes too.
        withForm("Actor", "RemoveShout", into: &registry) { _, bridge, actor, shout in
            let fromRecord = bridge.scriptState.recordShouts(of: actor).contains(shout)
            let knew = bridge.scriptState.knowsShout(shout, actor: actor, fromRecord: fromRecord)
            bridge.updateScriptedState(of: actor) { state in
                state.setFlag(ScriptedStateName.shout(shout), fromRecord ? false : nil)
                if state.form(equippedShoutName) == shout {
                    state.setForm(equippedShoutName, nil)
                }
            }
            return .returned(.boolean(knew))
        }
        withForm("Actor", "EquipShout", into: &registry) { _, bridge, actor, shout in
            bridge.updateScriptedState(of: actor) {
                $0.setForm(equippedShoutName, shout)
                $0.setFlag(ScriptedStateName.shoutUnequipped, nil)
            }
            return .returned(.none)
        }
        withForm("Actor", "UnequipShout", into: &registry) { _, bridge, actor, shout in
            let equipped = bridge.scriptState.equippedShout(of: actor)
            bridge.updateScriptedState(of: actor) { state in
                if state.form(equippedShoutName) == shout {
                    state.setForm(equippedShoutName, nil)
                }
                // A record shout stays readied until a script takes it off.
                if equipped == shout {
                    state.setFlag(ScriptedStateName.shoutUnequipped, true)
                }
            }
            return .returned(.none)
        }
        scriptState("Actor", "GetEquippedShout", into: &registry) { _, bridge, actor in
            let shout = bridge.scriptState.equippedShout(of: actor)
            return .returned(shout
                .map { handle($0, in: bridge) } ?? .none)
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
            guard
                let form = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
            else {
                return failure(call, "\(name) needs a form")
            }
            return body(call, bridge, key, form)
        }
    }
}

extension PapyrusWorldStateBridge.ScriptState {
    /// The shouts the actor's base record gives.
    func recordShouts(of actor: ReferenceKey) -> [ReferenceKey] {
        guard let base = bridge.baseObject(of: actor) else { return [] }
        return bridge.menus?.recordShouts(ofBase: base) ?? []
    }

    /// The shouts with `word` that the player had no way to use before: no script gave
    /// them, the record does not, and no other word of theirs is known.
    func shoutsGained(
        by word: ReferenceKey, slots: [ReferenceKey: [ReferenceKey?]], player: ReferenceKey
    ) -> Int {
        let state = bridge.scriptedState(of: player)
        let record = recordShouts(of: player)
        return MiscStats.shouts(with: word, slots: slots).count { shout in
            let known = (slots[shout] ?? []).contains { other in
                other.map { state.flag(ScriptedStateName.wordKnown($0)) == true } ?? false
            }
            return !known && !knowsShout(shout, actor: player, fromRecord: record.contains(shout))
        }
    }

    /// A script's `AddShout` or `RemoveShout` wins over the record's spell list.
    func knowsShout(_ shout: ReferenceKey, actor: ReferenceKey, fromRecord: Bool) -> Bool {
        scriptedState(of: actor).flag(ScriptedStateName.shout(shout)) ?? fromRecord
    }

    /// The shout `EquipShout` readied, else the first shout the record gives that no
    /// script removed or took off. OpenSky's reading: an actor readies its record shout.
    func equippedShout(of actor: ReferenceKey) -> ReferenceKey? {
        let state = scriptedState(of: actor)
        if let shout = state.form(ScriptedStateName.equippedShout) {
            return shout
        }
        guard state.flag(ScriptedStateName.shoutUnequipped) != true else { return nil }
        return recordShouts(of: actor).first {
            state.flag(ScriptedStateName.shout($0)) != false
        }
    }
}

extension PapyrusNativeFunctions.ShoutsNatives {
    private static func installWords(into registry: inout PapyrusNativeRegistry) {
        // `TeachWord(WordOfPower)` and `UnlockWord(WordOfPower)` act on the player. The CK
        // wiki's UnlockWord page: it also marks the word known, with no notice.
        let names: [(String, [@Sendable (ReferenceKey) -> String])] = [
            ("TeachWord", [ScriptedStateName.wordKnown]),
            ("UnlockWord", [ScriptedStateName.wordUnlocked, ScriptedStateName.wordKnown])
        ]
        for (name, flags) in names {
            withForm("Game", name, into: &registry) { _, bridge, player, word in
                let before = bridge.scriptedState(of: player)
                let known = before.flag(ScriptedStateName.wordKnown(word)) == true
                let unlocked = before.flag(ScriptedStateName.wordUnlocked(word)) == true
                let slots = bridge.menus?.shoutWordSlots() ?? [:]
                let gained = name == "TeachWord" && !known
                    ? bridge.scriptState.shoutsGained(by: word, slots: slots, player: player) : 0
                bridge.updateScriptedState(of: player) { state in
                    for flag in flags {
                        state.setFlag(flag(word), true)
                    }
                }
                if !known {
                    bridge.worldState.incrementMiscStat("Words Of Power Learned")
                }
                if gained > 0 {
                    bridge.worldState.incrementMiscStat("Shouts Learned", by: Int32(gained))
                }
                if name == "UnlockWord", !unlocked {
                    bridge.worldState.incrementMiscStat("Words Of Power Unlocked")
                    for stat in MiscStats.wordUnlocked(word, slots: slots) {
                        bridge.worldState.incrementMiscStat(stat)
                    }
                }
                if
                    name == "TeachWord", !known,
                    let text = bridge.itemNoticeLines.formName(of: word)
                {
                    bridge.ports.presenter?.postWorldNotice(.wordLearned(word: text))
                }
                return .returned(.none)
            }
        }
        withForm("Game", "IsWordUnlocked", into: &registry) { _, bridge, player, word in
            let state = bridge.scriptedState(of: player)
            return .returned(.boolean(state.flag(ScriptedStateName.wordUnlocked(word)) == true))
        }
    }
}
