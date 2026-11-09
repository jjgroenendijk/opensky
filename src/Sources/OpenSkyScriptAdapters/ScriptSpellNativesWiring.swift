// `ScriptPerkBindingsAdapter` joins the started session: what `wireSpellNatives` registered.

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

/// Connects `ScriptPerkBindingsAdapter` to the started session.
public struct ScriptSpellNativesWiring {
    public init(
        _ adapter: ScriptPerkBindingsAdapter,
        bridge: PapyrusWorldStateBridge,
        provider: WorldDataStores
    ) {
        bridge.magicNatives.casterRuntime = { [weak game = adapter.game] in game?.magic.caster }
        bridge.magicNatives.isCommandedActor = { [weak game = adapter.game] key in
            game?.magic.commanded.contains { $0.actor == key } ?? false
        }
        bridge.magicEffectStore = provider.magicEffectStore
        bridge.formListStore = provider.formListStore
        bridge.keywordStore = provider.locationStore?.keywords
        bridge.magicNatives.dispelEffects = { [weak game = adapter.game] holder, predicate in
            game?.magic.dispelEffects(on: holder, where: predicate) ?? 0
        }
        bridge.magicNatives.applySpellHit = { [weak game = adapter.game] hit in
            game?.magicWorld.applySpellHit(hit) ?? .none
        }
        bridge.magicNatives.trapSoul = { [weak game = adapter.game] victim, caster in
            guard case .trapped = game?.magic.trapSoul(of: victim, by: caster) else { return false }
            return true
        }
        _ = ScriptPerkNativesWiring(adapter, bridge: bridge)
    }
}
