// `MeleeCombatWorld` conformance: the answers the melee runtime needs, each a
// plain read off an existing session system. Known partial answers:
// - `meleeMaterial()` uses the ground material under the player.
// - `raiseCombatEvent(_:on:)` reaches only the player's graph, so a stagger on
//   an NPC answers false.

import AppKit
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension GameViewController: MeleeCombatWorld {
    var meleeAttacker: MeleeAttacker {
        guard let renderer else {
            return MeleeAttacker(key: .player, feet: SIMD3<Float>(), facing: 0)
        }
        return MeleeAttacker(
            key: .player,
            feet: renderer.walkController.feetPosition,
            capsule: renderer.walkController.capsule,
            facing: renderer.freeFlyCamera.yaw
        )
    }

    func meleeTargets() -> [MeleeTarget] {
        guard let streamer else { return [] }
        return streamer.residentActorEntries().compactMap { entry in
            guard let actor = entry.placedActor else { return nil }
            let moved = streamer.npcTransform(for: entry.key)
                ?? worldState.component(ReferenceTransformOverride.self, for: entry.key)
            return MeleeTarget(
                key: entry.key,
                feet: moved?.position ?? actor.placement.position
            )
        }
    }

    func meleeMaterial() -> FormID? {
        renderer?.walkController.groundMaterial
    }

    /// The player's fortify multiplier for a swing with `handType`, from
    /// `CombatFortifyBonus`. Without an actor-value runtime it answers 1.
    func meleeAttackMultiplier(handType: CombatHandType) -> Float {
        guard let runtime = actorValues.runtime else { return 1 }
        let fortify = CombatFortifyBonus.melee(handType: handType) {
            runtime.value(at: $0, on: .player)
        }
        // `Mod Attack Damage` (35) multiplies the fortify term, as UESP
        // "Skyrim:Weapons" gives: `... * (1 + perk effects) * (1 + item effects)`.
        return fortify * perkMultiplier(
            at: GameViewController.attackDamageEntryPoint, on: .player
        )
    }

    /// The blocker's fortify and perk term. `Mod Percent Blocked` (39) holds Shield
    /// Wall; the fortify half is the Block Modifier pair.
    func meleeBlockMultiplier(of target: ReferenceKey) -> Float {
        guard
            let runtime = actorValues.runtime,
            let holder = actorValueHolder(for: target)
        else { return 1 }
        let fortify = CombatFortifyBonus.block { runtime.value(at: $0, on: holder) }
        return fortify * perkMultiplier(
            at: GameViewController.percentBlockedEntryPoint, on: target
        )
    }

    func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind? {
        // The player answers from the graph state `blockStart` drives. Every
        // other actor answers from its 16.7 combat behavior machine, which is
        // how an NPC blocks the player's swing through the same formula the
        // player's guard reduces an NPC's blow with.
        guard target == .player else { return combat.runtime?.blockKind(of: target) }
        return melee.runtime?.state.isBlocking == true ? .weapon : nil
    }

    @discardableResult
    func applyMeleeDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        guard
            amount > 0,
            let runtime = actorValues.runtime,
            let holder = actorValueHolder(for: target)
        else { return false }
        runtime.damage(.health, by: amount, on: holder)
        return true
    }

    /// One landed blow reaches the scripts attached to its target. The archery and
    /// combat-loop seams share this path into the VM.
    @discardableResult
    func reportScriptHit(_ hit: ScriptHitEvent) -> Int {
        // Every landed blow passes here, so assault is noticed in one place.
        reportPlayerAssault(
            on: hit.target,
            wasHostile: combatHostility(of: hit.target) == .hostile,
            aggressor: hit.aggressor
        )
        return papyrus?.queueOnHit(hit) ?? 0
    }

    func playMeleeImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        guard
            let engine = renderer?.worldAudio, engine.isRunning,
            let sounds = (streamerCellProvider as? AudioDataProviding)?.soundStore,
            let sound = try? sounds.resolveAny(impact.sound),
            let path = sound.filePaths.first,
            let data = try? audioFileSystem?.contents(forPath: path)
        else { return }
        // A playback failure is logged by the engine and leaves the hit
        // silent; there is nothing this layer could do about it that would be
        // better than a silent hit.
        _ = try? engine.playPositional(
            fileData: data,
            request: AudioPlayRequest(
                name: path,
                category: sound.audioCategory ?? .footsteps,
                worldPosition: position
            )
        )
    }

    @discardableResult
    func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        guard let renderer else { return false }
        guard target == nil || target == .player else { return false }
        renderer.locomotion.raise(name)
        // `raisedEvents` holds the names the graph declared a home for and
        // `missingEvents` the ones it did not, so membership after the raise
        // is the graph's own answer rather than an assumption about it.
        return renderer.locomotion.status.raisedEvents.contains(name)
    }

    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        renderer?.locomotion.write(value, to: name)
    }

    /// The actor-value holder for a hit target: the player, or a resident ACHR
    /// resolved through the streamer. Nil when nothing resident answers to the
    /// key, which is a hit on an actor that was evicted mid-swing.
    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        if key == .player {
            return .player
        }
        guard
            let streamer,
            let entry = streamer.referenceEntry(key: key),
            let actor = entry.placedActor
        else { return nil }
        return ActorValueHolder(
            key: key,
            subject: .actor(base: actor.base),
            cell: streamer.cellLocation(of: key)
        )
    }
}
