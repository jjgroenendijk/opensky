// The magic condition seam: this session's spellbooks, active effects and casts
// as the snapshot `ConditionContext.magic` carries, and the panel's probe of
// the eight magic functions against the player.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyWorldState

extension MagicCoordinator {
    /// Known spells, active effects and cast state of the player and every
    /// resident actor. Empty without a caster, so a magic function reports the
    /// gap instead of answering about a spellbook nothing wrote.
    public func magicConditionResolution() -> MagicConditionResolution {
        guard let caster else { return .empty }
        var states: [ReferenceKey: MagicConditionState] = [:]
        let keys = [ReferenceKey.player]
            + (world?.residentActorKeys() ?? []).filter { $0 != .player }
        for key in keys {
            states[key] = MagicConditionState(
                spellbook: caster.spellbook.state(of: conditionHolder(for: key)),
                effects: caster.spellbook.store.component(ActiveEffectState.self, for: key)
                    ?? ActiveEffectState(),
                castingHands: Set(SpellHand.allCases.filter { hand in
                    caster.phase(of: hand, on: key).isCasting
                })
            )
        }
        return MagicConditionResolution(
            spells: caster.spellbook.spells,
            effects: effects?.effects,
            sourcePlugin: spellPluginName,
            states: states
        )
    }

    /// One line per magic function, run against the player. A function that
    /// cannot answer prints its reason, so a gap is not a zero.
    func magicConditionLines() -> [String] {
        guard let caster, let world else { return [] }
        let book = caster.spellbook.state(of: .player)
        let readied = book.spell(in: .right) ?? book.spell(in: .left)
        var context = ConditionContext()
        context.magic = magicConditionResolution()
        context.subject = .player
        context.target = .player
        return MagicCore.conditionProbes(readied: readied.flatMap(caster.spellbook.record))
            .map { probe in
                probe.line(value: world.conditionText(
                    of: probe.function, parameter: probe.parameter, in: context
                ))
            }
    }

    /// An actor the world cannot place reads an empty spellbook rather than
    /// throwing the whole snapshot away.
    private func conditionHolder(for key: ReferenceKey) -> ActorValueHolder {
        world?.actorValueHolder(for: key)
            ?? ActorValueHolder(key: key, subject: .generated, cell: nil)
    }
}
