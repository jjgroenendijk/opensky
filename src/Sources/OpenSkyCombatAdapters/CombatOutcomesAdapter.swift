import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `CombatOutcomesAdapter` reads from the session.
@MainActor
public protocol CombatOutcomesHost: AnyObject, SendableMetatype {
    var audio: any AudioPort { get }
    var combat: any CombatPort { get }
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
    public let game: any CombatOutcomesHost
    public let motion: CombatMotionAdapter
    public let impactEffects: CombatImpactEffectsAdapter
}

extension CombatOutcomesAdapter {
    /// A record without a sound level sounds at the normal level.
    private func noteSoundEvent(owner: ReferenceKey, level: UInt32?, at position: SIMD3<Float>) {
        guard let runtime = game.perception.runtime else { return }
        let level = level.flatMap(DetectionSoundLevel.init(rawValue:)) ?? .normal
        runtime.noteSoundEvent(
            owner: owner, level: runtime.settings.actionSound(for: level), at: position
        )
    }

    /// Runs what a combat step asked of the session.
    public func run(_ commands: [CombatCommand]) {
        for command in commands {
            switch command {
            case let .showNotification(text): game.hud.showNotification(text)
            case let .playImpact(impact, position): motion.playImpact(impact, at: position)
            case let .detectionEvent(owner, level, position):
                noteSoundEvent(owner: owner, level: level, at: position)
            case let .removeReference(key): game.worldState.reset(key)
            case .resetRagdolls: game.ragdoll.runtime?.reset()
            case let .setCombatMusic(active): game.audio.musicDirector?.setCombatActive(active)
            case let .playerAttackedOutsideCombat(use):
                game.storyWorld.commentOnPlayer(.playerAction(use == .swing ? "SWMW" : "FIWE"))
            case .drewBlood, .showDefaultBlood, .muzzleFlash: showImpact(command)
            case .incrementStat, .playerUsedWeapon: countStat(command)
            case .weaponFired, .rangedKillCam, .playerBowShot: runShot(command)
            }
        }
    }

    private func runShot(_ command: CombatCommand) {
        switch command {
        case let .weaponFired(weapon, shooter, position, firstPerson):
            weaponFired(weapon, by: shooter, at: position, firstPerson: firstPerson)
        case let .rangedKillCam(projectile, target):
            impactEffects.playRangedKillCam(projectile: projectile, target: target)
        case let .playerBowShot(weapon, ammunition, power):
            game.scripts.runtime?.queuePlayerBowShot(
                weapon: weapon, ammunition: ammunition, power: power,
                sunGazing: game.scripts.bridge?.isPlayerSunGazing ?? false
            )
        default: return
        }
    }

    /// The `XNAM` sound for the player in first person, else `SNAM`; then a detection
    /// event at the weapon's sound level.
    private func weaponFired(
        _ weapon: FormID, by shooter: ReferenceKey, at position: SIMD3<Float>, firstPerson: Bool
    ) {
        guard let details = game.combat.items?.weapon(weapon)?.details else { return }
        let sound = firstPerson
            ? details.firstPersonFireSound ?? details.fireSound : details.fireSound
        guard let sound else { return }
        game.audio.soundDirector?.playSound(formID: sound, source: shooter, at: position)
        noteSoundEvent(owner: shooter, level: details.detectionSoundLevel, at: position)
    }

    private func showImpact(_ command: CombatCommand) {
        switch command {
        case let .drewBlood(hit, target): impactEffects.drewBlood(hit, target: target)
        case let .showDefaultBlood(target, position, melee):
            impactEffects.showDefaultBlood(on: target, at: position, melee: melee)
        case let .muzzleFlash(visuals, position, direction):
            game.effectsWorld.showMuzzleFlash(visuals, at: position, along: direction)
        default: return
        }
    }

    private func countStat(_ command: CombatCommand) {
        switch command {
        case let .incrementStat(name): game.worldState.incrementMiscStat(name)
        case let .playerUsedWeapon(weapon):
            if let key = game.scripts.bridge?.referenceKey(forFormID: weapon) {
                game.worldState.noteFavoriteUse(.weapon, of: key)
            }
        default: return
        }
    }
}
