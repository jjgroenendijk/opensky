// `MagicWorldAdapter` joins the started session: what `wireMagic` registered.

import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// After `wireActorValues`, because every effect writes an actor value, and after
/// `wireWorldItems`, because the spellbook reads the equipment.
public struct MagicWiring {
    public init(_ adapter: MagicWorldAdapter, gameSession: GameSession) {
        let coordinator = adapter.game.magic
        // `Mod Spell Cost` folds through the caster's own copy of the perks.
        coordinator.caster?.perks = adapter.game.perks.runtime
        if coordinator.effects != nil {
            adapter.registerEffects(coordinator, gameSession: gameSession)
        }
        if coordinator.caster != nil {
            adapter.registerCasting(coordinator, gameSession: gameSession)
        }
    }
}
