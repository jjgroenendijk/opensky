// Slow Time: the player's running Slow Time effects set how fast the world and the
// player move. The magnitude is the world's share of normal speed. UESP "Skyrim:Slow
// Time": the player is "only slowed down to 70% of normal speed". Entry point 70 (Mod
// Player Magic Slowdown) changes that share; Quick Reflexes sets it to 1.
// See docs/engine/magic-archetypes.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMagicInterface
import OpenSkyProgressionInterface

nonisolated enum SlowTimeRule {
    /// The player's share of normal speed while time is slow, before entry point 70.
    static let playerShare: Float = 0.7
    /// Ours: a magnitude of 0 would stop the world and every clock that follows it.
    static let minimumWorldShare: Float = 0.01

    /// Each running effect, as its world share and the player's share. UESP "Skyrim:Block":
    /// Quick Reflexes "appears to stack with" Slow Time, so the shares multiply. The player
    /// never runs slower than the world.
    static func scales(_ effects: [(world: Float, player: Float)]) -> MagicTimeScales {
        var scales = MagicTimeScales.normal
        for effect in effects {
            let world = effect.world.isFinite ? min(max(effect.world, minimumWorldShare), 1) : 1
            let player = effect.player.isFinite ? min(max(effect.player, world), 1) : 1
            scales.world *= world
            scales.player *= player
        }
        scales.world = max(scales.world, minimumWorldShare)
        scales.player = max(scales.player, scales.world)
        return scales
    }
}

extension MagicCoordinator {
    /// The time scales the player's Slow Time effects set this frame.
    public var timeScales: MagicTimeScales {
        guard let runtime = effects, let player = world.actorValueHolder(for: .player) else {
            return .normal
        }
        let slowing = runtime.active(on: player).filter {
            !$0.isSuspended && runtime.rule(of: $0) == .world(.slowTime)
        }
        guard !slowing.isEmpty else { return .normal }
        return SlowTimeRule.scales(slowing.map { effect in
            (world: effect.peakMagnitude, player: playerShare(under: effect))
        })
    }

    /// Entry point 70 over the base share, with the effect's spell bound so a perk can
    /// test its keywords.
    private func playerShare(under effect: ActiveEffect) -> Float {
        var subjects = PerkEvaluationSubjects(owner: .player)
        var seams = ConditionContext()
        if
            effect.source.kind == .spell,
            let spells = caster?.spellbook.spells,
            let spell = spells.spell(key: effect.source.record)
        {
            subjects = subjects.binding(.spell, to: spells.conditionSubject(of: spell))
            seams.spellEvaluation = SpellEvaluationResolution(spell: spell)
        }
        return world.perkModified(
            SlowTimeRule.playerShare, at: .modPlayerMagicSlowdown, on: .player,
            subjects: subjects, seams: seams
        )
    }
}
