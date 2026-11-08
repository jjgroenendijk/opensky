import OpenSkyActorPresentation
import OpenSkyAudio
import OpenSkyCamera
public import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyEffects
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkySessionInterface
import OpenSkyWorldInterface
import simd

/// What `CombatImpactEffectsAdapter` reads from the session.
@MainActor
public protocol CombatImpactEffectsHost: AnyObject {
    var cinematicCamera: any CinematicCameraPort { get }
    var effects: any EffectsPort { get }
    var idleWorld: any IdleWorldPort { get }
    var menuWorld: any MenuWorldPort { get }
    var ragdollWorld: any RagdollWorldPort { get }
    var worldData: WorldDataStores? { get }
}

/// Part of `CombatWorldAdapter`, over its own narrow host.
public struct CombatImpactEffectsAdapter {
    public unowned let owner: CombatWorldAdapter
    public unowned let game: any CombatImpactEffectsHost
}

extension CombatImpactEffectsAdapter {
    public func showImpact(_ resolved: ResolvedMeleeImpact, at position: SIMD3<Float>) {
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
    public func impactMaterial(of actor: ReferenceKey) -> FormID? {
        guard
            let race = game.menuWorld.race(of: actor),
            let races = game.worldData?.actorValueBaselines?
                .resolver?.races
        else { return nil }
        return races[race.rawValue]?.details.materialType
    }

    /// The actor's RACE `DATA` flags, or nil without a resolved race.
    public func raceFlags(of actor: ReferenceKey) -> Race.Flags? {
        guard
            let race = game.menuWorld.race(of: actor),
            let races = game.worldData?.actorValueBaselines?.resolver?.races
        else { return nil }
        return races[race.rawValue]?.flags
    }

    /// A landed hit that bled: screen blood when the player was struck, and blood on
    /// a melee attacker's weapon unless the target's race keeps weapons clean.
    public func drewBlood(_ hit: CombatHitRecord, target: ReferenceKey) {
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
    public func showDefaultBlood(on target: ReferenceKey, at position: SIMD3<Float>, melee: Bool) {
        guard raceFlags(of: target)?.contains(.noBloodDecal) != true else { return }
        game.effects.showDefaultBlood(on: target, at: position, melee: melee)
    }

    public func actorFlies(_ actor: ReferenceKey) -> Bool {
        raceFlags(of: actor)?.contains(.flies) ?? false
    }

    public func canBeKilled(_ target: ReferenceKey, by attacker: ReferenceKey) -> Bool {
        game.ragdollWorld.zeroHealthOutcome(of: target, killer: attacker) == .dies
    }

    public func startKillMove(_ attempt: KillMoveAttempt) -> Bool {
        guard game.idleWorld.idles.startKillMove(
            attempt.action, attacker: attempt.attacker, target: attempt.target,
            kills: attempt.kills
        ) else { return false }
        if attempt.attacker == .player {
            game.cinematicCamera.playKillCam(
                attacker: .player, target: attempt.target, remainingHostiles: 0, force: true
            )
        }
        return true
    }

    public func isInKillMove(_ key: ReferenceKey) -> Bool {
        game.idleWorld.idles.pairedAnimation(of: key)?.isKillMove == true
    }
}
