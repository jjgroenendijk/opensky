// The summon side of `MagicWorld`: a summon is a spawned actor in the world state, so the
// next cell build places it; a reanimated corpse is resurrected. Ending either removes the
// spawn or kills the actor again. See docs/engine/magic-archetypes.md.

import Foundation
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyMagic
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension MagicWorldAdapter {
    func perkChoices(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> [PerkEntryPointChoice] {
        game.perks.choices(at: entryPoint, on: key, subjects: { _ in subjects }, seams: seams)
    }

    /// The summon faces its caster. It is placed in the caster's cell.
    func summonActor(_ base: FormID, at point: SIMD3<Float>?, for caster: ReferenceKey)
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
        return key
    }

    func reanimate(_ corpse: ReferenceKey, for _: ReferenceKey) -> Bool {
        guard
            game.actorWorld.combatActors().contains(where: { $0.key == corpse && $0.isDead }),
            let bridge = game.scripts.bridge
        else { return false }
        return bridge.resurrectActor(corpse)
    }

    /// Summons "fade out and leave no corpse" (CK wiki "Magic Effect").
    func releaseCommandedActor(_ actor: CommandedActor) {
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

    private func feet(of key: ReferenceKey) -> SIMD3<Float>? {
        guard key != .player else { return game.gameSession?.walkController.feetPosition }
        return game.scripts.bridge?.referenceState(for: key)?.transform.position
    }
}
