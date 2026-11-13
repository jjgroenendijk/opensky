// The Papyrus natives `ScriptPerkBindingsAdapter` fills as the bridge is built.

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension ScriptPerkBindingsAdapter {
    /// Fills these natives as the bridge is built.
    public func fillSpellNatives(bridge: PapyrusWorldStateBridge, provider: any WorldRecordsPort) {
        bridge.natives.magic.casterRuntime = { [weak game = self.game] in game?.magic.caster }
        bridge.natives.magic.isCommandedActor = { [weak game = self.game] key in
            game?.magic.commanded.contains { $0.actor == key } ?? false
        }
        bridge.stores.magicEffectStore = provider.magicEffectStore
        bridge.stores.formListStore = provider.formListStore
        bridge.stores.keywordStore = provider.locationKeywords
        bridge.natives.magic.dispelEffects = { [weak game = self.game] holder, predicate in
            game?.magic.itemUse.dispelEffects(on: holder, where: predicate) ?? 0
        }
        bridge.natives.magic.applySpellHit = { [weak game = self.game] hit in
            game?.magicWorld.applySpellHit(hit) ?? .none
        }
        bridge.natives.magic.trapSoul = { [weak game = self.game] victim, caster in
            guard case .trapped = game?.magic.soulTrapping.trapSoul(of: victim, by: caster)
            else { return false }
            return true
        }
        fillPerkNatives(bridge: bridge)
    }
}
