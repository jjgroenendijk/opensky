import Foundation
import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMagic
public import OpenSkyMagicInterface
import OpenSkyPlayer
import OpenSkyProgression
public import OpenSkyProgressionInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `MagicSummonedActorsAdapter` reads from the session.
@MainActor
public protocol MagicSummonedActorsHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var magic: any MagicPort { get }
    var perks: any PerkPort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `MagicWorldAdapter`, over its own narrow host.
public struct MagicSummonedActorsAdapter {
    public unowned let owner: MagicWorldAdapter
    public unowned let game: any MagicSummonedActorsHost
}

extension MagicSummonedActorsAdapter {
    public func perkChoices(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> [PerkEntryPointChoice] {
        game.perks.choices(at: entryPoint, on: key, subjects: { _ in subjects }, seams: seams)
    }

    /// The summon faces its caster. It is placed in the caster's cell.
    public func summonActor(_ base: FormID, at point: SIMD3<Float>?, for caster: ReferenceKey)
        -> ReferenceKey?
    {
        guard
            let streamer = game.streamer,
            let origin = feet(of: caster),
            let location = caster == .player
            ? streamer.currentCellLocation : streamer.cellLocation(of: caster)
        else { return nil }
        let position = point ?? origin
        let toward = origin - position
        let heading = simd_length(toward) > 1 ? atan2(toward.x, toward.y) : 0
        let placement = PlacedReference.Placement(
            position: position, rotation: SIMD3(0, 0, heading)
        )
        let spawn = ReferenceSpawnState(base: base, location: location, placement: placement)
        let key = game.worldState.allocateGeneratedKey()
        game.worldState.set(spawn, for: key, in: location)
        streamer.requestRebuild(of: location)
        enlist(key, for: caster)
        return key
    }

    public func reanimate(_ corpse: ReferenceKey, for caster: ReferenceKey) -> Bool {
        guard
            game.actorWorld.combatActors().contains(where: { $0.key == corpse && $0.isDead }),
            let bridge = game.scripts.bridge,
            bridge.resurrectActor(corpse) else { return false }
        enlist(corpse, for: caster)
        return true
    }

    /// The actor takes its caster's side: the player's ally is calm toward the player,
    /// and an NPC's ally shares its caster's regard for the player.
    public func enlist(_ actor: ReferenceKey, for caster: ReferenceKey) {
        guard let loop = game.combat.loop else { return }
        let regard = caster == .player ? ActorHostility.neutral : loop.hostility(of: caster)
        loop.setHostility(regard, on: actor)
        loop.command(actor, by: caster)
    }

    /// Summons "fade out and leave no corpse" (CK wiki "Magic Effect").
    public func stopCommandedActor(_ key: ReferenceKey) {
        game.combat.loop?.dismiss(key)
    }

    public func releaseCommandedActor(_ actor: CommandedActor) {
        game.combat.loop?.dismiss(actor.actor)
        switch actor.kind {
        case .summoned:
            let location = game.worldState.component(ReferenceSpawnState.self, for: actor.actor)?
                .location
            game.worldState.reset(actor.actor)
            if let location {
                game.streamer?.requestRebuild(of: location)
            }
        case .reanimated:
            _ = game.scripts.bridge?.killActor(actor.actor, killer: nil)
        }
    }

    public func isActorDead(_ key: ReferenceKey) -> Bool {
        game.combat.combatActor(key: key)?.isDead ?? false
    }

    private func feet(of key: ReferenceKey) -> SIMD3<Float>? {
        guard key != .player else { return game.gameSession?.walkController.feetPosition }
        return game.scripts.bridge?.referenceState(for: key)?.transform.position
    }

    public var shoutKnowledge: ShoutKnowledge {
        guard let state = game.scripts.bridge?.scriptedState(of: .player) else {
            return ShoutKnowledge()
        }
        var knowledge = ShoutKnowledge(equipped: state.form(ScriptedStateName.equippedShout))
        for (key, shout) in game.magic.shouts {
            if state.flag(ScriptedStateName.shout(key)) == true {
                knowledge.shouts.insert(key)
            }
            for word in shout.words.compactMap(\.word) {
                let wordKey = ReferenceKey(resolved: word.id)
                if state.flag(ScriptedStateName.wordKnown(wordKey)) == true {
                    knowledge.knownWords.insert(wordKey)
                }
                if state.flag(ScriptedStateName.wordUnlocked(wordKey)) == true {
                    knowledge.unlockedWords.insert(wordKey)
                }
            }
        }
        return knowledge
    }

    public func changeShoutKnowledge(_ change: ShoutKnowledgeChange) {
        game.scripts.bridge?.updateScriptedState(of: .player) { state in
            switch change {
            case let .addShout(shout): state.setFlag(ScriptedStateName.shout(shout), true)
            case let .equip(shout): state.setForm(ScriptedStateName.equippedShout, shout)
            case let .teachWord(word): state.setFlag(ScriptedStateName.wordKnown(word), true)
            case let .unlockWord(word): state.setFlag(ScriptedStateName.wordUnlocked(word), true)
            }
        }
    }
}
