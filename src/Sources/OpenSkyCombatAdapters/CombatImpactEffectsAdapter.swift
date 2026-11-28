import OpenSkyActorPresentation
import OpenSkyAudio
import OpenSkyCamera
import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyEffects
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
public import OpenSkySessionInterface
import OpenSkyWorldInterface
import simd

/// What `CombatImpactEffectsAdapter` reads from the session.
@MainActor
public protocol CombatImpactEffectsHost: AnyObject, SendableMetatype {
    var cinematicCamera: any CinematicCameraPort { get }
    var effects: any EffectsPort { get }
    var effectsWorld: any EffectsWorldPort { get }
    var idleWorld: any IdleWorldPort { get }
    var menuWorld: any MenuWorldPort { get }
    var ragdollWorld: any RagdollWorldPort { get }
    var combatRecords: (any CombatRecordsPort)? { get }
    var gameSession: (any GameSessionPort)? { get }
}

/// Part of `CombatWorldAdapter`, over its own narrow host.
public struct CombatImpactEffectsAdapter {
    public let game: any CombatImpactEffectsHost
}

extension CombatImpactEffectsAdapter {
    public func showImpact(_ resolved: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        guard let impact = resolved.impact else { return }
        let store = game.combatRecords?.footstepStore
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
    /// The spells of `actor`'s attacks, in list order, such as a creature's disease.
    public func attackSpells(of actor: ReferenceKey) -> [FormID] {
        game.menuWorld.attacks(of: actor).compactMap { $0.properties?.spell }
    }

    public func attacks(of actor: ReferenceKey) -> [RaceAttack] {
        game.menuWorld.attacks(of: actor)
    }

    /// The `ATKD` values of the attack `event` starts on `actor`.
    public func attackData(of actor: ReferenceKey, event: String) -> RaceAttack.Properties? {
        ActorAttackList.attack(game.menuWorld.attacks(of: actor), event: event)
    }

    public func impactMaterial(of actor: ReferenceKey) -> FormID? {
        guard
            let race = game.menuWorld.race(of: actor),
            let races = game.combatRecords?.actorValueBaselines?
                .resolver?.races
        else { return nil }
        return races[race.rawValue]?.details.materialType
    }

    /// The actor's RACE `DATA` flags, or nil without a resolved race.
    public func raceFlags(of actor: ReferenceKey) -> Race.Flags? {
        guard
            let race = game.menuWorld.race(of: actor),
            let races = game.combatRecords?.actorValueBaselines?.resolver?.races
        else { return nil }
        return races[race.rawValue]?.flags
    }

    /// A landed hit that bled: screen blood when the player was struck, and blood on
    /// a melee attacker's weapon unless the target's race keeps weapons clean.
    public func drewBlood(_ hit: CombatHitRecord, target: ReferenceKey) {
        guard bleeds(target) else { return }
        if target == .player {
            game.effects.splatterScreen(damage: hit.damage)
        }
        guard
            hit.kind == .melee, let attacker = hit.attacker,
            raceFlags(of: target)?.contains(.noWeaponBlood) != true
        else { return }
        game.effects.bloodyWeapon(of: attacker)
    }

    /// The decal of blood sprayed around a hit, on a world surface.
    public func placeBloodDecal(_ impact: Impact, at position: SIMD3<Float>, normal: SIMD3<Float>) {
        guard let decal = game.combatRecords?.footstepStore?.decal(of: impact) else { return }
        game.effects.placeImpactDecal(decal, at: position, normal: normal)
    }

    /// The race flags keep a bloodless body, such as a skeleton's, clean.
    public func showDefaultBlood(on target: ReferenceKey, at position: SIMD3<Float>, melee: Bool) {
        guard bleeds(target), raceFlags(of: target)?.contains(.noBloodDecal) != true else {
            return
        }
        game.effects.showDefaultBlood(on: target, at: position, melee: melee)
    }

    /// `ACBS` flag `0x10000` keeps every hit on the actor bloodless.
    func bleeds(_ actor: ReferenceKey) -> Bool {
        game.menuWorld.recordFlags(of: actor)?.contains(.doesNotBleed) != true
    }

    public func actorFlies(_ actor: ReferenceKey) -> Bool {
        raceFlags(of: actor)?.contains(.flies) ?? false
    }

    public func actorIsChild(_ actor: ReferenceKey) -> Bool {
        raceFlags(of: actor)?.contains(.child) ?? false
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
        // The player as victim watches from behind (docs/engine/paired-animations.md).
        if
            attempt.target == .player, let session = game.gameSession,
            session.movementMode == .walk
        {
            session.setMovementMode(.thirdPerson)
        }
        return true
    }

    /// The release check passed: the kill cam follows the shot.
    public func playRangedKillCam(projectile: Int, target: ReferenceKey) {
        game.cinematicCamera.playRangedKillCam(projectile: projectile, target: target)
    }

    public func isInKillMove(_ key: ReferenceKey) -> Bool {
        game.idleWorld.idles.pairedAnimation(of: key)?.isKillMove == true
    }
}
