// The Papyrus natives `ScriptPerkBindingsAdapter` fills as the bridge is built.

import OpenSkyActorPresentation
import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
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
    public func fillSpellNatives(bridge: PapyrusWorldStateBridge, provider: WorldDataStores) {
        bridge.magicNatives.casterRuntime = { [weak game = self.game] in game?.magic.caster }
        bridge.magicNatives.isCommandedActor = { [weak game = self.game] key in
            game?.magic.commanded.contains { $0.actor == key } ?? false
        }
        bridge.magicEffectStore = provider.magicEffectStore
        bridge.formListStore = provider.formListStore
        bridge.keywordStore = provider.locationStore?.keywords
        bridge.magicNatives.dispelEffects = { [weak game = self.game] holder, predicate in
            game?.magic.dispelEffects(on: holder, where: predicate) ?? 0
        }
        bridge.magicNatives.applySpellHit = { [weak game = self.game] hit in
            game?.magicWorld.applySpellHit(hit) ?? .none
        }
        bridge.magicNatives.trapSoul = { [weak game = self.game] victim, caster in
            guard case .trapped = game?.magic.trapSoul(of: victim, by: caster) else { return false }
            return true
        }
        fillPerkNatives(bridge: bridge)
    }
}
