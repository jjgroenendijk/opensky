// Who bleeds out at zero health, and what entering and leaving bleedout does to the
// rest of the session (docs/engine/ragdoll.md#bleedout).

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyCells
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState

extension RagdollWorldAdapter {
    /// An essential actor always bleeds out. A protected one bleeds out unless the
    /// player dealt the last blow (UESP "Skyrim:Protected NPCs").
    func zeroHealthOutcome(of key: ReferenceKey, killer: ReferenceKey?) -> ZeroHealthOutcome {
        guard let bridge = game.scripts.bridge else { return .dies }
        if bridge.scriptedState(of: key).flag(ScriptedStateName.deferredKill) == true {
            return .deferred
        }
        if baseFlag(ScriptedStateName.essential, .essential, of: key) {
            return .bleedsOut
        }
        if killer != .player, baseFlag(ScriptedStateName.protected, .protected, of: key) {
            return .bleedsOut
        }
        return .dies
    }

    func healthFraction(of key: ReferenceKey) -> Float? {
        guard let values = game.actorValues.runtime, let holder = holder(of: key) else {
            return nil
        }
        return values.fractions(of: holder)[.health]
    }

    func bleedoutThreshold(of key: ReferenceKey) -> Float? {
        guard
            let base = game.streamer?.referenceEntry(key: key)?.placedActor?.base,
            let resolver = game.worldData?.actorValueBaselines?.resolver
        else { return nil }
        return resolver.characterClass(ofBase: base)?.bleedoutDefault
    }

    func blocksBleedoutRecovery(of key: ReferenceKey) -> Bool {
        game.scripts.bridge?.scriptedState(of: key)
            .flag(ScriptedStateName.noBleedoutRecovery) == true
    }

    func restoreHealthShare(_ share: Float, of key: ReferenceKey) {
        guard let values = game.actorValues.runtime, let holder = holder(of: key) else { return }
        let missing = values.maximums(of: holder)[.health] - values.current(of: holder)[.health]
        let amount = min(values.maximums(of: holder)[.health] * share, missing)
        if amount > 0 {
            values.restore(.health, by: amount, on: holder)
        }
    }

    func enterBleedout(_ key: ReferenceKey) {
        game.scripts.bridge?.updateScriptedState(of: key) {
            $0.setFlag(ScriptedStateName.bleedingOut, true)
        }
        _ = game.actorGraphWorld.graphs.raise(RagdollGraphNames.bleedOutStart, on: key)
        _ = game.scripts.bridge?.stopActorCombat(key)
        game.scripts.runtime?.queueEnterBleedout(actor: key)
        announceWoundedTeammate(key)
    }

    /// OpenSky's reading of `sEssentialCharacterDown`: a follower going down is named.
    private func announceWoundedTeammate(_ key: ReferenceKey) {
        guard
            game.scripts.bridge?.scriptedState(of: key)
                .flag(ScriptedStateName.playerTeammate) == true,
            let streamer = game.streamer,
            let form = streamer.referenceEntry(key: key)?.formID,
            let name = streamer.interactionName(reference: form), !name.isEmpty
        else { return }
        let down = game.mapWorld.settingTexts(PlayerDeathText.self)[.essentialDown]
        game.hud.showNotification("\(name) \(down)")
    }

    /// The actor stands up with full health (UESP "Skyrim:Essential NPCs").
    func leaveBleedout(_ key: ReferenceKey) {
        game.scripts.bridge?.updateScriptedState(of: key) {
            $0.setFlag(ScriptedStateName.bleedingOut, nil)
        }
        if let values = game.actorValues.runtime, let holder = holder(of: key) {
            let missing = values.maximums(of: holder)[.health] - values.current(of: holder)[.health]
            if missing > 0 {
                values.restore(.health, by: missing, on: holder)
            }
        }
        _ = game.actorGraphWorld.graphs.raise(RagdollGraphNames.bleedOutStop, on: key)
    }

    /// A script's `SetEssential` or `SetProtected` on the base wins over the record flag.
    private func baseFlag(_ name: String, _ flag: ActorBase.Flags, of key: ReferenceKey) -> Bool {
        guard
            let bridge = game.scripts.bridge,
            let base = game.streamer?.referenceEntry(key: key)?.placedActor?.base
        else { return false }
        let scripted = bridge.referenceKey(forFormID: base)
            .flatMap { bridge.scriptedState(of: $0).flag(name) }
        return scripted ?? game.menuWorld.recordFlags(ofBase: base)?.contains(flag) ?? false
    }
}
