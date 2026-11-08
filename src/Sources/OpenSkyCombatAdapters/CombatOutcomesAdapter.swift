import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `CombatOutcomesAdapter` reads from the session.
@MainActor
public protocol CombatOutcomesHost: AnyObject {
    var audio: any AudioPort { get }
    var effectsWorld: any EffectsWorldPort { get }
    var hud: any HUDPort { get }
    var perception: any PerceptionPort { get }
    var ragdoll: any RagdollPort { get }
    var scripts: any ScriptPort { get }
    var storyWorld: any StoryWorldPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `CombatWorldAdapter`, over its own narrow host.
public struct CombatOutcomesAdapter {
    public unowned let owner: CombatWorldAdapter
    public unowned let game: any CombatOutcomesHost
}

extension CombatOutcomesAdapter {
    /// Runs what a combat step asked of the session.
    public func run(_ commands: [CombatCommand]) {
        for command in commands {
            switch command {
            case let .showNotification(text): game.hud.showNotification(text)
            case let .playImpact(impact, position): owner.playImpact(impact, at: position)
            case let .detectionEvent(owner, position):
                game.perception.runtime?.noteDetectionEvent(owner: owner, at: position)
            case let .removeReference(key): game.worldState.reset(key)
            case .resetRagdolls: game.ragdoll.runtime?.reset()
            case let .setCombatMusic(active): game.audio.musicDirector?.setCombatActive(active)
            case let .playerAttackedOutsideCombat(use):
                game.storyWorld.commentOnPlayer(.playerAction(use == .swing ? "SWMW" : "FIWE"))
            case let .drewBlood(hit, target): owner.impactEffects.drewBlood(hit, target: target)
            case let .playerBowShot(weapon, ammunition, power):
                game.scripts.runtime?.queuePlayerBowShot(
                    weapon: weapon, ammunition: ammunition, power: power,
                    sunGazing: game.scripts.bridge?.isPlayerSunGazing ?? false
                )
            case let .showDefaultBlood(target, position, melee):
                owner.impactEffects.showDefaultBlood(on: target, at: position, melee: melee)
            case let .muzzleFlash(visuals, position, direction):
                game.effectsWorld.showMuzzleFlash(visuals, at: position, along: direction)
            }
        }
    }
}
