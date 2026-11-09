import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyBehavior
public import OpenSkyCells
import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `CombatReportsAdapter` reads from the session.
@MainActor
public protocol CombatReportsHost: AnyObject {
    var controllerRumble: any ControllerRumblePort { get }
    var crime: any CrimePort { get }
    var dialogue: any DialoguePort { get }
    var magic: any MagicPort { get }
    var magicWorld: any MagicWorldPort { get }
    var perception: any PerceptionPort { get }
    var progression: any ProgressionPort { get }
    var scripts: any ScriptPort { get }
    var storyWorld: any StoryWorldPort { get }
    var worldData: WorldDataStores? { get }
}

/// Part of `CombatWorldAdapter`, over its own narrow host.
public struct CombatReportsAdapter {
    public let game: any CombatReportsHost
    public let actorFacts: CombatActorFactsAdapter
}

extension CombatReportsAdapter {
    /// Every landed blow passes here, so assault is noticed in one place.
    @discardableResult
    public func reportScriptHit(_ hit: ScriptHitEvent) -> Int {
        let wasHostile = actorFacts.hostility(of: hit.target) == .hostile
        game.crime.reportAssault(on: hit.target, wasHostile: wasHostile, aggressor: hit.aggressor)
        if hit.aggressor == .player {
            game.perception.runtime?.noteAttack(by: .player)
        }
        game.scripts.bridge?.recordHit(hit, targetWasHostile: wasHostile)
        speakCombatLines(for: hit)
        rumbleWeapon(for: hit)
        return game.scripts.runtime?.queueOnHit(hit) ?? 0
    }

    /// The player's own weapon blow shakes the controller with the weapon's Rumble tab.
    private func rumbleWeapon(for hit: ScriptHitEvent) {
        guard
            hit.aggressor == .player, hit.delivery == .melee || hit.delivery == .ranged,
            let source = hit.source,
            let weapon = game.worldData?.inventoryBaselines?.items.weapon(source)
        else { return }
        game.controllerRumble.weapon(weapon.rumble)
    }

    /// An NPC aggressor may call out its attack and an NPC target its hurt, each held back
    /// by its own `SpeechTimerSettings` window and chance. A hit below
    /// `fCombatSpeakHitThreshold` of the target's health stays silent; a spell hit carries
    /// no damage yet, so it is not held back.
    private func speakCombatLines(for hit: ScriptHitEvent) {
        let now = game.storyWorld.sceneSeconds
        let maximum = actorFacts.health(of: hit.target)?.maximum ?? 0
        let hurtSpeaks = hit.delivery == .spell
            || game.dialogue.speechTimers.hitSpeaks(damage: hit.damage, maximumHealth: maximum)
        var lines: [(NPCSpeechLine, ReferenceKey)] = [(.combatAttack, hit.aggressor)]
        if hurtSpeaks {
            lines.append((.combatHit, hit.target))
        }
        for (line, speaker) in lines where speaker != .player {
            guard
                let id = game.dialogue.combatLine(line, speaker: speaker, now: now),
                let info = game.dialogue.runtime?.dialogue.info(id)
            else { continue }
            let seconds = game.storyWorld.lineDuration(of: info, speaker: speaker)
            game.storyWorld.speak(
                info: id, speaker: speaker, lookAt: nil,
                seconds: seconds ?? SceneLine.defaultSeconds
            )
        }
    }

    @discardableResult
    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        game.progression.reportSkillUse(use)
    }

    @discardableResult
    public func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        game.magicWorld.applySpellHit(hit)
    }

    @discardableResult
    public func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        game.magic.applyWeaponEnchantment(hit)
    }

    public func applyWeaponPoison(_ hit: WeaponPoisonHit) {
        game.magic.applyWeaponPoison(hit)
    }

    @discardableResult
    public func applyWeaponEnhancement(attacker: ReferenceKey, target: ReferenceKey) -> Int {
        game.magic.applyWeaponEnhancement(attacker: attacker, target: target)
    }

    public func spellLanded(_ payload: SpellPayload, at point: SIMD3<Float>) {
        game.magic.spellLanded(payload, at: point)
    }
}
