// The magic condition seam's live builder (issue #474, roadmap item 19.11):
// turns this session's spellbooks, active effects and casts into the immutable
// snapshot `ConditionContext.magic` carries.
//
// A satellite of its own rather than another method on the conditions file for
// the reason `GameViewControllerCasting.swift` is separate from
// `GameViewControllerMagic.swift`: this reads three runtimes and two record
// stores, and a reader chasing "where does `HasSpell` get its answer" should
// land on one screen.
//
// The actor set is the one `runtimeStateActorResolution()` already uses — the
// player plus every resident actor the combat pass knows — so the magic
// functions and the actor functions answer about the same population. An actor
// outside it is a reason-tagged failure rather than a spellless stranger.

import AppKit

extension GameViewController {
    /// Known spells, active effects and cast state for every actor this session
    /// tracks, plus the stores a magic condition's FormID parameter resolves
    /// against.
    ///
    /// Empty without a caster runtime, which is every synthetic scene: the
    /// magic functions then report the gap instead of answering about an actor
    /// whose spellbook nothing has ever written.
    func magicConditionResolution() -> MagicConditionResolution {
        guard let caster = casting.runtime else { return .empty }
        var states: [ReferenceKey: MagicConditionState] = [:]
        for key in magicConditionActors() {
            states[key] = MagicConditionState(
                spellbook: caster.spellbook.state(of: magicHolder(for: key)),
                effects: worldState.component(ActiveEffectState.self, for: key)
                    ?? ActiveEffectState(),
                castingHands: Set(SpellHand.allCases.filter { hand in
                    caster.phase(of: hand, on: key).isCasting
                })
            )
        }
        return MagicConditionResolution(
            spells: caster.spellbook.spells,
            effects: magicEffects.runtime?.effects,
            sourcePlugin: casting.spellPluginName,
            states: states
        )
    }

    /// The player and every resident actor, deduplicated and in a stable order.
    private func magicConditionActors() -> [ReferenceKey] {
        var keys: [ReferenceKey] = [.player]
        for observation in combatActors() where observation.key != .player {
            keys.append(observation.key)
        }
        return keys
    }

    /// The spellbook is keyed by `ActorValueHolder`, and a resident actor's
    /// holder needs its base record. An actor the streamer cannot place falls
    /// back to a bare key, which reads an empty spellbook rather than throwing
    /// the whole snapshot away.
    private func magicHolder(for key: ReferenceKey) -> ActorValueHolder {
        if key == .player {
            return .player
        }
        guard
            let streamer,
            let actor = streamer.referenceEntry(key: key)?.placedActor
        else {
            return ActorValueHolder(key: key, subject: .generated, cell: nil)
        }
        return ActorValueHolder(
            key: key,
            subject: .actor(base: actor.base),
            cell: streamer.cellLocation(of: key)
        )
    }
}
