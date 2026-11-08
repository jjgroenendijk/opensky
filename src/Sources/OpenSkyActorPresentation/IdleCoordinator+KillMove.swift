// Kill moves: an attack whose idle tree picks a paired idle plays it on the attacker and
// its target. See docs/engine/paired-animations.md#kill-moves.

import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface

extension IdleCoordinator {
    /// Plays the paired idle the tree under `action` picks, with `ShouldAttackKill` read
    /// as `kills`. False when an unpaired attack idle wins or no idle passes.
    public func startKillMove(
        _ action: String, attacker: ReferenceKey, target: ReferenceKey, kills: Bool
    ) -> Bool {
        guard let store, attacker != target, let now = world?.idleAnimationTime else {
            return false
        }
        let roots = store.roots(underAction: action)
        guard !roots.isEmpty else { return false }
        let resolution = AttackKillResolution(attacks: [
            AttackKillResolution.Attack(attacker: attacker, target: target, kills: kills)
        ])
        let selection = selector(for: attacker, target: target) { context in
            context.attackKills = resolution
        }.select(roots: roots)
        guard
            let chosen = selection.chosen,
            let event = chosen.record.animationEvent,
            PairedAnimationCore.isPaired(event: event)
        else { return false }
        firePaired(PairedAnimationPlay(
            lead: attacker, partner: target, idle: chosen.record.editorID ?? chosen.id.description,
            event: event, start: now
        ), trace: selection.trace)
        return pairedAnimation(of: attacker) != nil
    }
}
