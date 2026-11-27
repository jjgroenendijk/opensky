import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
public import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMagic
public import OpenSkyMagicInterface
import OpenSkyPlayer
public import OpenSkyProgressionInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `MagicSummonedActorsAdapter` reads from the session.
@MainActor
public protocol MagicSummonedActorsHost: AnyObject, SendableMetatype {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var combatWorld: any CombatWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var magic: any MagicPort { get }
    var perception: any PerceptionPort { get }
    var perks: any PerkPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `MagicWorldAdapter`, over its own narrow host.
public struct MagicSummonedActorsAdapter {
    public let game: any MagicSummonedActorsHost
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
    public func summonActor(_ base: FormID, at aim: SummonAim, for caster: ReferenceKey)
        -> ReferenceKey?
    {
        let streamer = game.streamer
        guard
            let origin = feet(of: caster),
            let location = caster == .player
            ? streamer.currentCellLocation : streamer.cellLocation(of: caster)
        else { return nil }
        let position = switch aim {
        case let .point(point): point
        case let .ahead(searchRadius):
            ahead(of: caster, at: origin, base: base, searchRadius: searchRadius)
        }
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
        game.perception.runtime?.noteSummon(by: caster, at: position)
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
                game.streamer.requestRebuild(of: location)
            }
        case .reanimated:
            _ = game.scripts.bridge?.killActor(actor.actor, killer: nil)
        }
    }

    public func isActorDead(_ key: ReferenceKey) -> Bool {
        game.combat.combatActor(key: key)?.isDead ?? false
    }

    /// Room in front of a self-cast summon's caster, stopped short of the first wall
    /// a cylinder of the summon's radius meets on the way.
    private func ahead(
        of caster: ReferenceKey, at feet: SIMD3<Float>, base: FormID, searchRadius: Float
    ) -> SIMD3<Float> {
        let summonRadius = game.actorValues.runtime?.baselines
            .baseline(for: .actor(base: base)).footprintRadius ?? 0
        let reach = SummonAim.reach(
            casterRadius: footprintRadius(of: caster), summonRadius: summonRadius,
            searchRadius: searchRadius
        )
        let aim = SummonAim.aheadPoint(feet: feet, yaw: yaw(of: caster), reach: reach)
        return SummonAim.standingPoint(from: feet, toward: aim, summonRadius: summonRadius) {
            game.combatWorld.freeDistance(of: $0, radius: $1, along: $2, upTo: $3)
        }
    }

    private func yaw(of key: ReferenceKey) -> Float {
        guard key != .player else { return game.combat.meleeAttacker.facing }
        return game.actorWorld.combatActor(key: key)?.yaw ?? 0
    }

    private func footprintRadius(of key: ReferenceKey) -> Float {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return 0 }
        return runtime.baseline(of: holder).footprintRadius
    }

    private func feet(of key: ReferenceKey) -> SIMD3<Float>? {
        guard key != .player else { return game.gameSession?.walkController.feetPosition }
        return game.scripts.bridge?.referenceState(for: key)?.transform.position
    }

    var shoutKnowledge: ShoutKnowledge {
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
        if
            case let .unlockWord(word) = change, let bridge = game.scripts.bridge,
            bridge.scriptedState(of: .player).flag(ScriptedStateName.wordUnlocked(word)) != true
        {
            game.worldState.incrementMiscStat("Words Of Power Unlocked")
        }
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
