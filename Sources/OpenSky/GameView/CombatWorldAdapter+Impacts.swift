// The visual half of a melee or projectile impact: its model and decal through the
// effects coordinator, and the race material an actor's body counts as.

import OpenSkyAudio
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorld
import simd

extension CombatWorldAdapter {
    func showImpact(_ resolved: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        guard let impact = resolved.impact else { return }
        let store = (game.worldData as? AudioDataProviding)?.footstepStore
        let surface: ImpactSurface = if let target = resolved.target {
            .actor(target)
        } else if let normal = resolved.surfaceNormal {
            .surface(normal: normal)
        } else {
            .ground
        }
        game.effects.showImpact(
            impact, decal: store?.decal(of: impact), at: position, on: surface
        )
    }

    /// The race's `NAM4`, so a blade on flesh finds the blood impact.
    func impactMaterial(of actor: ReferenceKey) -> FormID? {
        guard
            let race = game.menuWorld.race(of: actor),
            let races = (game.worldData as? ActorValueDataProviding)?.actorValueBaselines?
                .resolver?.races
        else { return nil }
        return races[race.rawValue]?.details.materialType
    }
}
