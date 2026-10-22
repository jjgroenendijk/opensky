// The visual half of a melee or projectile impact: its model and decal through the
// effects coordinator, and the race material an actor's body counts as.

import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombat
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

extension CombatWorldAdapter {
    func showImpact(_ resolved: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        guard let impact = resolved.impact else { return }
        let store = game.worldData?.footstepStore
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
            let races = game.worldData?.actorValueBaselines?
                .resolver?.races
        else { return nil }
        return races[race.rawValue]?.details.materialType
    }

    /// The actor's RACE `DATA` flags, or nil without a resolved race.
    func raceFlags(of actor: ReferenceKey) -> Race.Flags? {
        guard
            let race = game.menuWorld.race(of: actor),
            let races = game.worldData?.actorValueBaselines?.resolver?.races
        else { return nil }
        return races[race.rawValue]?.flags
    }

    /// A landed hit that bled: screen blood when the player was struck, and blood on
    /// a melee attacker's weapon unless the target's race keeps weapons clean.
    func drewBlood(_ hit: CombatHitRecord, target: ReferenceKey) {
        if target == .player {
            game.effects.splatterScreen(damage: hit.damage)
        }
        guard
            hit.kind == .melee, let attacker = hit.attacker,
            raceFlags(of: target)?.contains(.noWeaponBlood) != true
        else { return }
        game.effects.bloodyWeapon(of: attacker)
    }

    /// The race flags keep a bloodless body, such as a skeleton's, clean.
    func showDefaultBlood(on target: ReferenceKey, at position: SIMD3<Float>, melee: Bool) {
        guard raceFlags(of: target)?.contains(.noBloodDecal) != true else { return }
        game.effects.showDefaultBlood(on: target, at: position, melee: melee)
    }

    func actorFlies(_ actor: ReferenceKey) -> Bool {
        raceFlags(of: actor)?.contains(.flies) ?? false
    }
}
