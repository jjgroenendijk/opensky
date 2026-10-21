// Summon Creature and Reanimate: the session places or raises the actor, the coordinator
// keeps who commands whom, and the end of the effect sends the actor away. Entry point
// 68 sets how many a caster commands; entry point 53 picks a spell for a reanimated
// actor. The rules live in `SummonCore`. See docs/engine/magic-archetypes.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension MagicCoordinator {
    func performCommanding(_ action: MagicWorldAction) {
        switch action.phase {
        case .began where action.archetype == .summon: summon(action)
        case .began: reanimate(action)
        case .ended: release(action)
        }
    }

    /// How many actors `caster` may command at once.
    public func commandLimit(of caster: ReferenceKey) -> Int {
        let limit = world.perkModified(
            SummonCore.baseCommandLimit, at: .modCommandedActorLimit, on: caster,
            subjects: PerkEvaluationSubjects(owner: caster), seams: ConditionContext()
        )
        return limit.isFinite ? max(1, Int(limit.rounded())) : 1
    }

    /// The panel line: who the player commands, against the limit.
    var commandedText: String {
        let mine = commanded.filter { $0.caster == .player }
        let names = mine.compactMap { world.actorValueHolder(for: $0.actor) }
            .map(world.actorName)
        let list = names.isEmpty ? "" : ": " + names.joined(separator: ", ")
        return "Commanded: \(mine.count) of \(commandLimit(of: .player))\(list)"
    }

    private func summon(_ action: MagicWorldAction) {
        let caster = action.caster ?? action.target.key
        guard
            let item = associatedItem(of: action.effect),
            let base = effects?.effects.loadOrderFormID(item),
            let actor = world.summonActor(
                base, at: summonPoints.removeValue(forKey: caster), for: caster
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
        guard world.reanimate(corpse, for: caster) else {
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
            let spell = world.perkChoices(
                at: .applyReanimateSpell, on: caster,
                subjects: PerkEvaluationSubjects(owner: caster, target: actor),
                seams: ConditionContext()
            ).lazy.compactMap(\.spell).first
        else { return }
        applySpellHit(SpellHit(
            payload: spell.payload(caster: caster), targets: [SpellHitTarget(key: actor)]
        ))
    }

    /// Past the limit the caster's oldest actor goes, and the effect that held it ends.
    private func command(_ actor: CommandedActor) {
        let outcome = SummonCore.commanding(
            actor, in: commanded, limit: commandLimit(of: actor.caster)
        )
        commanded = outcome.kept
        for old in outcome.released {
            world.releaseCommandedActor(old)
            dispel(old.sequence, on: old.holder)
        }
    }

    private func release(_ action: MagicWorldAction) {
        guard let index = SummonCore.ending(action.sequence, on: action.target.key, in: commanded)
        else { return }
        world.releaseCommandedActor(commanded.remove(at: index))
    }

    private func dispel(_ sequence: UInt64, on key: ReferenceKey) {
        guard let holder = world.actorValueHolder(for: key) else { return }
        withEffects { $0.dispel(on: holder) { $0.sequence == sequence } }
    }
}
