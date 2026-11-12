// Summon Creature and Reanimate: the session places or raises the actor, the coordinator
// keeps who commands whom, and the end of the effect sends the actor away. Entry point
// 68 sets how many a caster commands; entry point 53 picks a spell for a reanimated
// actor. The rules live in `SummonCore`. See docs/engine/magic-archetypes.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension MagicCoordinator.SummonCommands {
    func performCommanding(_ action: MagicWorldAction) {
        switch action.phase {
        case .began where action.archetype == .summon: summon(action)
        case .began: reanimate(action)
        case .ended: release(action)
        }
    }

    /// How many actors `caster` may command at once.
    func commandLimit(of caster: ReferenceKey) -> Int {
        let limit = coordinator.world.perkModified(
            SummonCore.baseCommandLimit, at: .modCommandedActorLimit, on: caster,
            subjects: PerkEvaluationSubjects(owner: caster), seams: ConditionContext()
        )
        return limit.isFinite ? max(1, Int(limit.rounded())) : 1
    }

    /// "On death, the creature automatically fades out": a fallen actor ends its effect,
    /// and the end sends it away.
    func advanceCommanded(delta: Float) {
        for actor in coordinator.commanded where coordinator.world.isActorDead(actor.actor) {
            dispel(actor.sequence, on: actor.holder)
        }
        let step = delta.isFinite ? max(delta, 0) : 0
        coordinator.fadingSummons = coordinator.fadingSummons.map { ($0.actor, $0.seconds - step) }
        for gone in coordinator.fadingSummons where gone.seconds <= 0 {
            coordinator.world.releaseCommandedActor(gone.actor)
        }
        coordinator.fadingSummons.removeAll { $0.seconds <= 0 }
    }

    /// A summon stays `fSummonedCreatureFadeOutSeconds` before it goes; a raised corpse
    /// falls at once.
    private func send(_ actor: CommandedActor) {
        guard actor.kind == .summoned, coordinator.rules.summons.fadeOutSeconds > 0 else {
            coordinator.world.releaseCommandedActor(actor)
            return
        }
        coordinator.world.stopCommandedActor(actor.actor)
        coordinator.fadingSummons.append((actor, coordinator.rules.summons.fadeOutSeconds))
    }

    /// How far each dismissed summon has faded, 0 to 1, over `fSummonedCreatureFadeOutSeconds`.
    var summonFades: [ReferenceKey: Float] {
        let total = coordinator.rules.summons.fadeOutSeconds
        guard total > 0 else { return [:] }
        return coordinator.fadingSummons.reduce(into: [:]) { fades, entry in
            fades[entry.actor.actor] = min(max(1 - entry.seconds / total, 0), 1)
        }
    }

    private func summon(_ action: MagicWorldAction) {
        let caster = action.caster ?? action.target.key
        guard
            let item = coordinator.associatedItem(of: action.effect),
            let base = coordinator.effects?.effects.loadOrderFormID(item),
            let actor = coordinator.world.summonActor(
                base, at: coordinator.summonPoints.removeValue(forKey: caster), for: caster
            )
        else { return }
        command(CommandedActor(
            actor: actor, caster: caster, kind: .summoned, holder: action.target.key,
            sequence: action.sequence
        ))
    }

    /// A target that is not dead ends the effect at once.
    private func reanimate(_ action: MagicWorldAction) {
        let corpse = action.target.key
        let caster = action.caster ?? .player
        guard coordinator.world.reanimate(corpse, for: caster) else {
            dispel(action.sequence, on: corpse)
            return
        }
        command(CommandedActor(
            actor: corpse, caster: caster, kind: .reanimated, holder: corpse,
            sequence: action.sequence
        ))
        applyReanimateSpell(caster: caster, on: corpse)
    }

    /// Dark Souls: the caster's chosen spell lands on the actor it raised.
    private func applyReanimateSpell(caster: ReferenceKey, on actor: ReferenceKey) {
        guard
            let spell = coordinator.world.perkChoices(
                at: .applyReanimateSpell, on: caster,
                subjects: PerkEvaluationSubjects(owner: caster, target: actor),
                seams: ConditionContext()
            ).lazy.compactMap(\.spell).first
        else { return }
        coordinator.casterBridge.applySpellHit(SpellHit(
            payload: spell.payload(caster: caster), targets: [SpellHitTarget(key: actor)]
        ))
    }

    /// Past the limit the caster's oldest actor goes, and the effect that held it ends.
    private func command(_ actor: CommandedActor) {
        let outcome = SummonCore.commanding(
            actor, in: coordinator.commanded, limit: commandLimit(of: actor.caster)
        )
        coordinator.commanded = outcome.kept
        for old in outcome.released {
            send(old)
            dispel(old.sequence, on: old.holder)
        }
    }

    private func release(_ action: MagicWorldAction) {
        guard let index = SummonCore.ending(
            action.sequence,
            on: action.target.key,
            in: coordinator.commanded
        )
        else { return }
        send(coordinator.commanded.remove(at: index))
    }

    private func dispel(_ sequence: UInt64, on key: ReferenceKey) {
        guard let holder = coordinator.world.actorValueHolder(for: key) else { return }
        coordinator.withEffects { $0.dispel(on: holder) { $0.sequence == sequence } }
    }
}
