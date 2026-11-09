import Foundation
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// What `EffectsTrapControlAdapter` reads from the session.
@MainActor
public protocol EffectsTrapControlHost: AnyObject {
    var effects: any EffectsPort { get }
    var combat: any CombatPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var hazardWorld: any HazardWorldPort { get }
    var hazards: any HazardPort { get }
    var magic: any MagicPort { get }
    var magicWorld: any MagicWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `EffectsWorldAdapter`, over its own narrow host.
public struct EffectsTrapControlAdapter {
    public let game: any EffectsTrapControlHost
    public let state: EffectsPartState
    public let bodyImpulses: EffectsBodyImpulsesAdapter
    public let locator: EffectsLocatorAdapter
}

extension EffectsTrapControlAdapter {
    /// The cell rebuild that the write starts makes the collision simulate or hold.
    /// A body made to hold keeps the pose it has now, not its last resting one.
    public func setMotionType(
        _ motionType: ReferenceMotionType,
        of reference: ReferenceKey
    ) -> Bool {
        guard let cell = game.streamer.cellLocation(of: reference) else { return false }
        if motionType == .keyframed, let body = game.streamer.dynamicBodies.body(for: reference) {
            let pose = PlacedReference.Placement(
                position: body.originPosition,
                rotation: MatrixMath.eulerAngles(of: body.orientation)
            )
            let current = game.scripts.bridge?.referenceState(for: reference)?.transform
            if current.map({ !Self.isSamePose(pose, as: $0.position, $0.rotation) }) ?? true {
                game.worldState.set(
                    ReferenceTransformOverride(
                        position: pose.position, rotation: pose.rotation,
                        scale: current?.scale ?? 1
                    ),
                    for: reference, in: cell
                )
            }
            game.streamer.dynamicBodies.remove(reference)
        }
        game.worldState.set(motionType, for: reference, in: cell)
        return true
    }

    /// Closer than this, in units, a body has not moved.
    private static let samePlace: Float = 0.01
    /// Closer than this, in radians, a body has not turned.
    private static let sameAngle: Float = 0.0001

    /// A body that never moved needs no transform write, which would rebuild the cell.
    private static func isSamePose(
        _ pose: PlacedReference.Placement, as position: SIMD3<Float>, _ rotation: SIMD3<Float>
    ) -> Bool {
        simd_distance(pose.position, position) < samePlace
            && simd_reduce_max(simd_abs(pose.rotation - rotation)) < sameAngle
    }

    /// Clears the moves and the motion type, or moves the object to `target`. Its
    /// inventory and other state stay. An actor is not reset.
    public func resetReference(_ reference: ReferenceKey, to target: ReferenceKey?) -> Bool {
        let streamer = game.streamer
        guard
            streamer.referenceEntry(key: reference)?.placedActor == nil
        else { return false }
        streamer.dynamicBodies.remove(reference)
        game.worldState.reset(.motionType, for: reference)
        guard
            let target,
            let destination = game.scripts.bridge?.referenceState(for: target)?.transform
        else {
            game.worldState.reset(.transform, for: reference)
            return true
        }
        let scale = game.scripts.bridge?.referenceState(for: reference)?.transform.scale ?? 1
        game.worldState.set(
            ReferenceTransformOverride(
                position: destination.position, rotation: destination.rotation, scale: scale
            ),
            for: reference, in: streamer.cellLocation(of: reference)
        )
        return true
    }

    /// The CK wiki "Fire - Weapon": a shot from a non-actor needs `akAmmo`, spends no
    /// ammunition, and leaves along the source's heading. Its damage is the weapon's
    /// plus the arrow's, with no skill or perk, and the weapon's enchantment applies.
    public func fireWeapon(
        _ weapon: ReferenceKey, from source: ReferenceKey, ammunition: ReferenceKey?
    ) -> Bool {
        guard
            let items = game.combat.items, let bridge = game.scripts.bridge,
            let runtime = game.combat.archery,
            let weaponID = bridge.localFormID(of: weapon), let bow = items.weapon(weaponID),
            let ammunitionID = ammunition.flatMap(bridge.localFormID(of:)),
            let arrow = items.archeryAmmunition(ammunitionID),
            let shooter = shooter(at: source)
        else { return false }
        var payload = ArrowPayload(
            damage: ArcheryDamage.resolve(
                bowDamage: Float(bow.damage), arrowDamage: arrow.damage, skill: 0
            ),
            weapon: weaponID,
            ammunition: arrow.item,
            enchantment: game.magic.enchantmentProfile(of: weaponID)
        )
        payload.spendsAmmunition = false
        let shot = ProjectileShot(profile: arrow.profile, payload: .arrow(payload))
        return runtime.projectiles.fire(shot, from: shooter) != nil
    }

    private func shooter(at source: ReferenceKey) -> ProjectileShooter? {
        guard let transform = game.scripts.bridge?.referenceState(for: source)?.transform else {
            return nil
        }
        return ProjectileShooter(
            key: source,
            origin: transform.position,
            aim: ProjectileShooter.headingAim(zRotation: transform.rotation.z),
            isFirstPerson: false,
            location: game.streamer.cellLocation(of: source)
        )
    }
}

extension EffectsTrapControlAdapter {
    public func placeAtMe(
        _ base: ReferenceKey,
        at anchor: ReferenceKey,
        count: Int
    ) -> ReferenceKey? {
        guard let position = locator.trapPosition(of: anchor) else { return nil }
        if let spec = game.hazardWorld.hazardSpec(for: base) {
            var last: ReferenceKey?
            for _ in 0 ..< max(1, count) {
                let key = state.nextHazardKey()
                game.hazards.spawn(HazardPlacement(id: key, spec: spec, position: position))
                last = key
            }
            return last
        }
        guard let spec = game.combat.explosions.spec(for: base) else { return spawn(
            base,
            at: anchor,
            count: count
        ) }
        for _ in 0 ..< max(1, count) {
            game.combat.explosions.detonate(spec, at: position, cause: .script)
        }
        // An explosion leaves no reference a script can hold.
        return nil
    }

    /// Papyrus impulses are in Havok units; the bodies simulate in game units.
    public func applyImpulse(_ impulse: SIMD3<Float>, to reference: ReferenceKey) -> Bool {
        guard let body = game.streamer.dynamicBodies.body(for: reference) else { return false }
        game.streamer.dynamicBodies.applyImpulse(
            impulse * NIFCollisionModel.havokToEngineScale, at: body.position, to: reference
        )
        return true
    }

    /// The player and an NPC slide on their capsules. The game also ragdolls an NPC
    /// that `PushActorAway` hits; OpenSky does not.
    public func pushActor(
        _ actor: ReferenceKey, awayFrom source: ReferenceKey,
        along direction: SIMD3<Float>?, speed: Float
    ) -> Bool {
        guard
            speed != 0, speed.isFinite,
            let feet = locator.trapPosition(of: actor) else { return false }
        let away = direction ?? locator.trapPosition(of: source).map { feet - $0 } ?? .zero
        let flat = SIMD3(away.x, away.y, 0)
        guard simd_length(flat) > 0 else { return false }
        return bodyImpulses.knockActor(
            actor,
            velocity: simd_normalize(flat) * speed,
            knockdown: false
        )
    }

    public func knockDownActor(
        _ actor: ReferenceKey, awayFrom source: ReferenceKey, magnitude: Float
    ) -> Bool {
        guard let from = locator.trapPosition(of: source) else { return false }
        return bodyImpulses.knockDown(actor, from: from, magnitude: magnitude)
    }

    public func staggerActor(_ actor: ReferenceKey, magnitude: Float) -> Bool {
        game.magicWorld.staggerActor(actor, magnitude: magnitude)
    }

    /// Any other base becomes `count` spawned references, and the last one is answered.
    private func spawn(_ base: ReferenceKey, at anchor: ReferenceKey, count: Int) -> ReferenceKey? {
        guard let bridge = game.scripts.bridge else { return nil }
        var last: ReferenceKey?
        for _ in 0 ..< max(1, count) {
            last = bridge.spawnReference(of: base, at: anchor) ?? last
        }
        return last
    }
}

extension EffectsTrapControlAdapter {
    public func playEffect(
        _ effect: ReferenceKey, on target: ReferenceKey, duration: Float?, facing: ReferenceKey?
    ) -> Bool {
        game.effects.attach(
            effect, to: .actor(target), cause: .script, duration: duration, facing: facing
        ) != nil
    }

    public func stopEffect(_ effect: ReferenceKey, on target: ReferenceKey) -> Bool {
        game.effects.detach(effect, from: .actor(target)) > 0
    }

    public func applyImageSpaceModifier(
        _ modifier: ReferenceKey, strength: Float, held: Bool, fadeSeconds: Float
    ) -> Bool {
        guard let gameSession = game.gameSession else { return false }
        return game.effects.startModifier(
            modifier, strength: strength, looping: held, fadeIn: fadeSeconds,
            on: &gameSession.imageSpace
        )
    }

    public func removeImageSpaceModifier(_ modifier: ReferenceKey, fadeSeconds: Float) {
        guard let gameSession = game.gameSession else { return }
        game.effects.stopModifier(modifier, fadeOut: fadeSeconds, on: &gameSession.imageSpace)
    }
}
